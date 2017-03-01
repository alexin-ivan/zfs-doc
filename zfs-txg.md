## Транзакционные группы (TXG)

В ZFS присутствует концепция транзакционной записи данных. Транзакционность предоставляет возможность "атомарной" записи блоков данных:
в случае возникновения ошибок при записи, все новые данные будут отброшены. Также это позволяет объединять запись нескольких блоков
в одну операцию, что добавляет некоторую последовательность записи (sequential writings), которая увеличивает быстродействие.
Кроме того, номера транзакционных групп могут использоваться для определения "возраста" блоков при "лечении", импорте или отправке пула.

Для увеличения производительности запись производится в рамках транзакционных групп (`txg`).
Обычно транзакционная группа ассоциируется с некоторым числом (номером транзакционной группы).

Рассмотрим вначале состояния, в которых может пребывать `TXG` (всего их 3, задаётся макросом `TXG_CONCURRENT_STATES`):

1. Opening - транзакционная группа "открыта" для добавления новых транзакций.

2. Quiescsing - освобождаются все блокировки, которыми захватываются транзакции в группе, группа переходит в состояние "стабилизации".

3. Syncing - после стабилизации группа переходит в состояние синхронизации - записи данных на диск.

Как было замечено, транзакционные группы идентифицируются при помощи номеров (типа `uint64_t`).
Структуры, хранящие данные групп имеют размер, равный 4 (`TXG_SIZE`, следующая после `TXG_CONCURRENT_STATES` степень двойки). 
Таким образом, есть 4 состояния:

* открытое;

* стабилизированное;

* синхронизирующееся;

* синхронизированное;

Благодаря битовой маске, равной 3 (`TXG_MASK = TXG_SIZE - 1`) и инкрементации номера транзакций, эти структуры образуют подобие кольцевого буфера.

Один из авторов ZFS утверждал, что можно было обойтись без состояния "стабилизации", однако это повлекло бы за собой переписывание большого объёма кода.

Рассмотрим использование данного механизма на примере функции `zvol_write` (`zvol.c`). 
Данная функция вызвывается в случае, если блочному устройству `zvol` пришёл запрос на запись.
Функция принимает в качестве аргумента структуру тип `bio` (`<linux-src>/include/linux/blk-types.h`), 
которая содержит в себе флаги (запись/чтение, сброс), "приватные" данные блочного устройства, смещение и размер данных, и буфер для данных.

```c
static int zvol_write(struct bio *bio)
{
	zvol_state_t *zv = bio->bi_bdev->bd_disk->private_data;
	uint64_t offset = BIO_BI_SECTOR(bio) << 9;
	uint64_t size = BIO_BI_SIZE(bio);
	int error = 0;
	dmu_tx_t *tx;
	rl_t *rl;
```

Вначале, если есть необходимость, происходит сброс данных в `ZIL`. Если в запросе отсутствуют данные на запись, то функция завершает свою работу.

```c
//zvol_write
	if (bio->bi_rw & VDEV_REQ_FLUSH)
		zil_commit(zv->zv_zilog, ZVOL_OBJ);

	if (size == 0)
		goto out;
```

Если данные для записи присутствуют, то начинается их запись.
Получаем блокировку на запись для области `[offset, offset + size]`. Эта блокировка работает только на уровне `zvol`:

```c
//zvol_write
	rl = zfs_range_lock(&zv->zv_znode, offset, size, RL_WRITER);
```

Следующий шаг - создание транзакции:

```c
//zvol_write
	tx = dmu_tx_create(zv->zv_objset);
```

Рассмотрим код этой функции. Вначале аллоцируется и инициализируется транзакционная группа,
привязанная к `DSL Directory` датасета. При инициализации создаётся список блокировок (`tx->tx_holds`)
который в дальнейшем будет использоваться для добавления данных в транзакционную группу.
Затем в `tx` устанавливается значение `tx->tx_objset` и значение номера транзакционной группы,
в которой производилась запись последнего снапшота (или имела место неудачная попытка записи этого снапшота).

```c
dmu_tx_t * dmu_tx_create(objset_t *os)
{
	dmu_tx_t *tx = dmu_tx_create_dd(os->os_dsl_dataset->ds_dir);
	tx->tx_objset = os;
	tx->tx_lastsnap_txg = dsl_dataset_prev_snap_txg(os->os_dsl_dataset);
	return (tx);
}
```

После создания транзакционной группы необходимо произвести захват пространства `[offset, offset + size]`
в объекте `ZVOL_OBJ`. Захват позволяет добавить необходимые данные в транзакционную группу `tx`.

```c
//zvol_write
	dmu_tx_hold_write(tx, ZVOL_OBJ, offset, size);
```

Рассмотрим подробнее:

```c
void dmu_tx_hold_write(dmu_tx_t *tx, uint64_t object, uint64_t off, int len)
{
	dmu_tx_hold_t *txh;
	txh = dmu_tx_hold_object_impl(tx, tx->tx_objset, object, THT_WRITE, off, len);
	if (txh == NULL)
		return;
	dmu_tx_count_write(txh, off, len);
	dmu_tx_count_dnode(txh);
}
```

В функцию `dmu_tx_hold_object_impl` передаётся новый аргумент - тип захвата (`dmu_tx_hold_type`).
В данном случае это `THT_WRITE`. Он используется в отладочных целях.
Рассмотрим упрощённый код данной функции:

```c

static dmu_tx_hold_t *
dmu_tx_hold_object_impl(dmu_tx_t *tx, objset, object) {
	dnode_t dnode = NULL;
	if is exists(object)
	{
		dnode = dnode_hold(objset, object, tx);
		lock(dnode->dn_mtx);
		dnode->assigned_txg = tx->txg;
		addref to dnode->dn_tx_holds by tx;
		unlock(dnode->dn_mtx)
	}
	dmu_tx_hold_t txh = alloc();
	txh->tx = tx;
	tx->dnode = dnode;
	list_insert_tail(tx->holds, txh);
	return txh;
}
```

Из кода видно, что если объект (`dnode`) уже существует, то его необходимо захватить и присвоить ему соответствующую транзакционную группу.
Потом необходимо создать объект, который будет удерживать этот захват (`dmu_tx_hold_t`) и добавить этот объект в список захватов данной группы (`tx->holds`).

Функция `dnode_hold` вызывает функцию `dnode_hold_impl`, которая захватывает `object` в `objset` и возвращает `dnode_t`, которая ему соответствует.
При захвате `dnode` вначале считывается с диска `dnode_phys` из `MetaNode` (мета-объекта), а затем добавляются захваты в `MetaNode` и в саму `dnode`.

Вернёмся назад по стеку функций. Вызов `dmu_tx_hold_object_impl` возвращает объект, который удерживает захват группы. 
Данный объект и значения `(offset, size)` передаются в функцию `dmu_tx_count_write`. Ещё задача - определить количество данных, которое будет записано.

Этапы выполнения этой функции:

1. Проверка (посредством чтения) первого и последнего блоков на уровне 0 и проверка всех блоков первого уровня.

2. Определение максимального/минимального размера блока (`min_bs, max_bs`) и размера косвенного блока (`min_ibs = max_ibs = dn->dn_indblkshift`);


Функция `dmu_tx_count_dnode` подобна функции `dmu_tx_count_write`, однако она определяет количество данных, которое будет записано в самой `dnode`.

Итак, мы создали транзакцию и захватили её. Теперь необходимо присвоить её транзакционной группе. Для этого вызываем функцию `dmu_tx_assign`:

```c
// zvol_write
	error = dmu_tx_assign(tx, TXG_WAIT);
	if (error) {
		dmu_tx_abort(tx);
		zfs_range_unlock(rl);
		goto out;
	}
```

Функция `dmu_tx_assign` принимает 2 аргумента - транзакцию и способ присваивания:

1. `TXG_WAIT` - если текущая открытая группа заполнена, то ожидать новую.

2. `TXG_NOWAIT` - неблокирующий вызов. В случае, если открытая группа заполнена, будет возвращено управление и код `ERESTART`.

3. `TXG_WAITED` - как TXG_NOWAIT, но указывает на то, что `dmu_tx_wait` уже вызвана от имени этой операции (хотя скорее всего на другой транзакции).

Рассмотрим упрощённый код функции (c учётом того, что мы используем `TXG_WAIT`).
В цикле мы пытаемся добавить (присвоить) транзакцию в группу. Если этого не удаётся сделать,
например, потому что группа заполнена (или другая причина, по которой был возвращён код `ERESTART`),

```c
int dmu_tx_assign(dmu_tx_t *tx)
{
	int err;
	while ((err = dmu_tx_try_assign(tx, TXG_WAIT)) != 0) {
		dmu_tx_unassign(tx);
		if (err != ERESTART)
			return (err);
		dmu_tx_wait(tx);
	}

	txg_rele_to_quiesce(&tx->tx_txgh);
	return (0);
}
```

Рассмотрим код функции `dmu_tx_try_assign`:

```c
static int
dmu_tx_try_assign(dmu_tx_t *tx, txg_how_t txg_how)
{
	dmu_tx_hold_t *txh;
	spa_t *spa = tx->tx_pool->dp_spa;
	uint64_t memory, asize, fsize, usize;
	uint64_t towrite, tofree, tooverwrite, tounref, tohold, fudge;

```

Вначале мы проверяем, нужна ли задержка для заполнения транзакционной группы (см. раздел "Задержка транзакций"):

```c
// dmu_tx_try_assign
	if (!tx->tx_waited && dsl_pool_need_dirty_delay(tx->tx_pool)) {
		tx->tx_wait_dirty = B_TRUE;
		return (ERESTART);
	}
```

Если мы попали сюда, то значит, что ждать новые транзакции нам не нужно.
Производим захват транзакционной группы (см. раздел "Особенности реализации транзакционных групп").

```c
// dmu_tx_try_assign
	tx->tx_txg = txg_hold_open(tx->tx_pool, &tx->tx_txgh);
	tx->tx_needassign_txh = NULL;
```

Затем проходим по всему списку объектов, которые удерживаются данной транзакцией.

Если объекту была назначена предыдущая транзакция, то его необходимо переназначить на текущую. Уходим с кодом `ERESTART`.

Если объекту не была назначена транзакция, то сразу назначаем ему текущую.

Увеличиваем счётчик владения объектом (объект используется данной транзакцией).

Затем увеличиваем счётчики количества записанных/освобождённых данных.

```c
// dmu_tx_try_assign
	towrite = tofree = tooverwrite = tounref = tohold = fudge = 0;
	for (txh = list_head(&tx->tx_holds); txh; txh = list_next(&tx->tx_holds, txh)) {
		dnode_t *dn = txh->txh_dnode;
		if (dn != NULL) {
			mutex_enter(&dn->dn_mtx);
			if (dn->dn_assigned_txg == tx->tx_txg - 1) {
				mutex_exit(&dn->dn_mtx);
				tx->tx_needassign_txh = txh;
				DMU_TX_STAT_BUMP(dmu_tx_group);
				return (SET_ERROR(ERESTART));
			}
			if (dn->dn_assigned_txg == 0)
				dn->dn_assigned_txg = tx->tx_txg;
			refcount_add(&dn->dn_tx_holds, tx);
			mutex_exit(&dn->dn_mtx);
		}
		towrite += txh->txh_space_towrite;
		tofree += txh->txh_space_tofree;
		tooverwrite += txh->txh_space_tooverwrite;
		tounref += txh->txh_space_tounref;
		tohold += txh->txh_memory_tohold;
		fudge += txh->txh_fudge;
	}
```

Если после того, как мы определили счётчики `towrite, tofree, etc`, был сделан снапшот,
то мы не сможем ничего перезаписать или освободить:

```c
// dmu_tx_try_assign
	if (tx->tx_objset &&
	    dsl_dataset_prev_snap_txg(tx->tx_objset->os_dsl_dataset) >
	    tx->tx_lastsnap_txg) {
		towrite += tooverwrite;
		tooverwrite = tofree = 0;
	}
```

Учтём наихудший вариант событий:

Максимальной четности `RAID-Z` блоки размером в один сектор (`ashift`), в этом случае требуется в `(VDEV_RAIDZ_MAXPARITY + 1)` раз больше места.
Добавим к этому тот факт, что мы можем иметь до 3 `DVA` на один `BP`, а ещё умножим на 2, потому что блок может быть дублирован до 3 `DVA` в `ddt_sync`.
Таким образом получим дефолтное значение параметра модуля `spa_asize_inflation`:

```c
spa_asize_inflation = (VDEV_RAIDZ_MAXPARITY + 1) * SPA_DVAS_PER_BP * 2 = 24
```

Функция `spa_get_asize` производит умножение этого коэффициента на входной аргумент и отдаёт результат.
Таким образом, мы получаем самые "худшие" значения параметров:

```c
// dmu_tx_try_assign
	/* needed allocation: worst-case estimate of write space */
	asize = spa_get_asize(tx->tx_pool->dp_spa, towrite + tooverwrite);
	/* freed space estimate: worst-case overwrite + free estimate */
	fsize = spa_get_asize(tx->tx_pool->dp_spa, tooverwrite) + tofree;
	/* convert unrefd space to worst-case estimate */
	usize = spa_get_asize(tx->tx_pool->dp_spa, tounref);
	/* calculate memory footprint estimate */
	memory = towrite + tooverwrite + tohold;
```

Теперь необходимо запросить у `DSL Directory` датасета, сможет ли он выделить необходимое количество ресурсов,
и в случае успеха можно переходить к следующему этапу.

```c
// dmu_tx_try_assign
	if (tx->tx_dir && asize != 0) {
		int err = dsl_dir_tempreserve_space(tx->tx_dir, memory,
		    asize, fsize, usize, &tx->tx_tempreserve_cookie, tx);
		if (err)
			return (err);
	}

	return (0);
}
```


В случае неудачи, например, потому что группа заполнена (или другая причина, по которой был возвращён код `ERESTART`), 
в цикле функции `dmu_tx_assign` будет выполнены `dmu_tx_unassign` и `dmu_tx_wait`.

Рассмотрим `dmu_tx_unassign`. 
Освобождаем "захват" открытой транзакции и очищаем присвоенные объектам (`dnode`) номера транзакций, затем освобождаем транзакцию.

```c
static void dmu_tx_unassign(dmu_tx_t *tx)
{
	dmu_tx_hold_t *txh;

	if (tx->tx_txg == 0)
		return;

```

Вначале освободим блокировки в дескрипторе открытой транзакционной группы:

```c
	txg_rele_to_quiesce(&tx->tx_txgh);
```

Затем пройдёмся по всему списку "захвата", проведём освобождение каждого объекта (`dnode`),
который с ним ассоциирован и уведомим об этом ожидающих, сбрасывая `refcount` в 0.

```c
	for (txh = list_head(&tx->tx_holds); txh != tx->tx_needassign_txh;
	    txh = list_next(&tx->tx_holds, txh)) {
		dnode_t *dn = txh->txh_dnode;

		if (dn == NULL)
			continue;
		mutex_enter(&dn->dn_mtx);
		ASSERT3U(dn->dn_assigned_txg, ==, tx->tx_txg);

		if (refcount_remove(&dn->dn_tx_holds, tx) == 0) {
			dn->dn_assigned_txg = 0;
			cv_broadcast(&dn->dn_notxholds);
		}
		mutex_exit(&dn->dn_mtx);
	}
```

После этого можно освободить сам дескриптор:

```
	txg_rele_to_sync(&tx->tx_txgh);

	tx->tx_lasttried_txg = tx->tx_txg;
	tx->tx_txg = 0;
}
```

Теперь перейдём к функции `dmu_tx_wait`:

```c
void dmu_tx_wait(dmu_tx_t *tx)
{
	spa_t *spa = tx->tx_pool->dp_spa;
	dsl_pool_t *dp = tx->tx_pool;
	hrtime_t before;

	before = gethrtime();
```

Теперь, если нам необходимо подождать, пока не придут
новые данные (т.е. дождаться, когда заполнится транзакционная группа):

```c
// dmu_tx_wait
	if (tx->tx_wait_dirty) {
		uint64_t dirty;
		mutex_enter(&dp->dp_lock);
		if (dp->dp_dirty_total >= zfs_dirty_data_max)
			DMU_TX_STAT_BUMP(dmu_tx_dirty_over_max);
		while (dp->dp_dirty_total >= zfs_dirty_data_max)
			cv_wait(&dp->dp_spaceavail_cv, &dp->dp_lock);
		dirty = dp->dp_dirty_total;
		mutex_exit(&dp->dp_lock);

		dmu_tx_delay(tx, dirty);

		tx->tx_wait_dirty = B_FALSE;
		tx->tx_waited = B_TRUE;
```

Иначе, если пул приостановлен или мы ещё не пытались добавить транзакцию в группу,
то дождёмся завершится синхронизация:

```c
// dmu_tx_wait
	} else if (spa_suspended(spa) || tx->tx_lasttried_txg == 0) {
		/*
		 * If the pool is suspended we need to wait until it
		 * is resumed.  Note that it's possible that the pool
		 * has become active after this thread has tried to
		 * obtain a tx.  If that's the case then tx_lasttried_txg
		 * would not have been set.
		 */
		txg_wait_synced(dp, spa_last_synced_txg(spa) + 1);
```

Если в `dmu_tx_try_assign` было установлено, что имела место попытка добавить данную `dnode`
в предыдущую группу, и она не добавилась (`dnode`), то дожидаемся особождения захватов,
связанных с этим объектом.

```c
// dmu_tx_wait
	} else if (tx->tx_needassign_txh) {
		dnode_t *dn = tx->tx_needassign_txh->txh_dnode;

		mutex_enter(&dn->dn_mtx);
		while (dn->dn_assigned_txg == tx->tx_lasttried_txg - 1)
			cv_wait(&dn->dn_notxholds, &dn->dn_mtx);
		mutex_exit(&dn->dn_mtx);
		tx->tx_needassign_txh = NULL;
```
Иначе - `dnode` уже находится в "стабилизирующейся" группе. Просто дождёмся пока данная
группа стабилизируется.

```c
// dmu_tx_wait
	} else {
		/*
		 * A dnode is assigned to the quiescing txg.  Wait for its
		 * transaction to complete.
		 */
		txg_wait_open(tx->tx_pool, tx->tx_lasttried_txg + 1);
	}
```

Добавляем затраченное время в статистику. В файле `/proc/spl/<pool-name>/dmu_tx_assign`
хранится гистограмма, показывающая распределение времени ожидания добавления транзакций в группы.

```c
// dmu_tx_wait
	spa_tx_assign_add_nsecs(spa, gethrtime() - before);
}
```

Итак, нам удалось добавить транзакцию в группу. Теперь транзакция `tx` принадлежит
открытой группу транзакций, держа соответствующие `hold`'ы.
На следующем этапе нам необходимо записать данные `bio` в объект `ZVOL` в рамках транзакции `tx`.

```c
// zvol_write
	error = dmu_write_bio(zv->zv_objset, ZVOL_OBJ, bio, tx);
```

Рассмотрим подробнее эту функцию:

```c
dmu_write_bio(objset_t *os, uint64_t object, struct bio *bio, dmu_tx_t *tx)
{
	uint64_t offset = BIO_BI_SECTOR(bio) << 9;
	uint64_t size = BIO_BI_SIZE(bio);
	dmu_buf_t **dbp;
	int numbufs, i, err;
	size_t bio_offset;

	if (size == 0)
		return (0);
```

Инициируем чтение блока данных `[offset, offset + size]` и их захват в 
буферы системы `DMU` (`DBUF`).

```c
// dmu_write_bio
	err = dmu_buf_hold_array(os, object, offset, size, FALSE, FTAG,
	    &numbufs, &dbp);
	if (err)
		return (err);
```

В функции `dmu_buf_hold_array` захватывается вначале объект (`dnode`),
а потом - блок данных этого объекта:

```c
static int dmu_buf_hold_array(objset_t *os, uint64_t object, uint64_t offset,
    uint64_t length, int read, void *tag, int *numbufsp, dmu_buf_t ***dbpp)
{
	dnode_t *dn;
	int err;

	err = dnode_hold(os, object, FTAG, &dn);
	if (err)
		return (err);

	err = dmu_buf_hold_array_by_dnode(dn, offset, length, read, tag,
	    numbufsp, dbpp, DMU_READ_PREFETCH);

	dnode_rele(dn, FTAG);

	return (err);
}
```

Рассмотрим `dmu_buf_hold_array_by_dnode`:

```c
int dmu_buf_hold_array_by_dnode(dnode_t *dn, uint64_t offset, uint64_t length,
    int read, void *tag, int *numbufsp, dmu_buf_t ***dbpp, uint32_t flags)
{
	dmu_buf_t **dbp;
	uint64_t blkid, nblks, i;
	uint32_t dbuf_flags;
	int err;
	zio_t *zio;

	dbuf_flags = DB_RF_CANFAIL | DB_RF_NEVERWAIT | DB_RF_HAVESTRUCT;
	if (flags & DMU_READ_NO_PREFETCH || length > zfetch_array_rd_sz)
		dbuf_flags |= DB_RF_NOPREFETCH;

	rw_enter(&dn->dn_struct_rwlock, RW_READER);
```

Вычисляем количество блоков (равное количеству буферов),
которые нам необходимо захватить и аллоцируем такое же количество буферов:

```c
// dmu_buf_hold_array_by_dnode
	if (dn->dn_datablkshift) {
		int blkshift = dn->dn_datablkshift;
		nblks = (P2ROUNDUP(offset+length, 1ULL<<blkshift) -
		    P2ALIGN(offset, 1ULL<<blkshift)) >> blkshift;
	} else {
		if (offset + length > dn->dn_datablksz) {
			// zfs_panic_recover(...)
			rw_exit(&dn->dn_struct_rwlock);
			return (SET_ERROR(EIO));
		}
		nblks = 1;
	}
	dbp = kmem_zalloc(sizeof (dmu_buf_t *) * nblks, KM_SLEEP);
```

Создаём ZIO-объект, который будет родителем для запросов на чтение
блоков данных.

Затем получаем индекс косвенного блока, по адресу `offset`, равный
$offset / ( 2 ^ {dn\_datablkshift})$ при помощи `dbuf_whichblock`.

Затем проходим по всем блокам и захватываем их.
Захват блока выполняет рекурсивный поиск, доходя до `L0`-блоков.
В процессе выполнения этой функции из ARC считываются косвенные блоки
при помощи функции `dbuf_read`. Подробности работы этой функции (`dbuf_hold`)
изложены в разделе ["DBUF/Реализация COW-механизма в DBUF"](#реализация-cow-механизма-в-dbuf)


```c
// dmu_buf_hold_array_by_dnode
	zio = zio_root(dn->dn_objset->os_spa, NULL, NULL, ZIO_FLAG_CANFAIL);
	blkid = dbuf_whichblock(dn, offset);
	for (i = 0; i < nblks; i++) {
		dmu_buf_impl_t *db = dbuf_hold(dn, blkid+i, tag);
		if (db == NULL) {
			rw_exit(&dn->dn_struct_rwlock);
			dmu_buf_rele_array(dbp, nblks, tag);
			zio_nowait(zio);
			return (SET_ERROR(EIO));
		}
		/* initiate async i/o */
		if (read) {
			(void) dbuf_read(db, zio, dbuf_flags);
		}
		dbp[i] = &db->db;
	}
	rw_exit(&dn->dn_struct_rwlock);
```

Запускаем ZIO-конвейер:

```c
	err = zio_wait(zio);
	if (err) {
		dmu_buf_rele_array(dbp, nblks, tag);
		return (err);
	}
```

Ожидаем завершения асинхронных операций чтения посредством
ожидания перехода dbuf'ов в состояние READ (прочитано с диска/кэша) или FILL (заполнено, ввод/вывод не был задействован):

```c
	/* wait for other io to complete */
	if (read) {
		for (i = 0; i < nblks; i++) {
			dmu_buf_impl_t *db = (dmu_buf_impl_t *)dbp[i];
			mutex_enter(&db->db_mtx);
			while (db->db_state == DB_READ ||
			    db->db_state == DB_FILL)
				cv_wait(&db->db_changed, &db->db_mtx);
			if (db->db_state == DB_UNCACHED)
				err = SET_ERROR(EIO);
			mutex_exit(&db->db_mtx);
			if (err) {
				dmu_buf_rele_array(dbp, nblks, tag);
				return (err);
			}
		}
	}
```

И возвращаем полученный массив объектов `dbuf`:


```c

	*numbufsp = nblks;
	*dbpp = dbp;
	return (0);
}
```

Вернёмся к функции `dmu_write_bio`. После захвата буферов с данными (блоками данных)
нам необходимо записать в них значения из `bio`.

Обратите внимание, что в случае, если размер блока данных, предназначенных
для копирования равен размеру буфера, то старые данные не будут прочитаны с диска/кэша,
т.к. они не нужны - блок данных будет перезаписан (точнее записан в новом месте - не забываем о COW)
полностью. Если же буфер перезаписывается не полностью, то нам необходимо записать остатки
старых данных в новое место.

После чтения/заполнения буфера, он будет помечен как "грязный" (`dbuf_dirty`) - подлежащий сбросу на диск.

```c
// dmu_write_bio
	bio_offset = 0;
	for (i = 0; i < numbufs; i++) {
		uint64_t tocpy;
		int64_t bufoff;
		int didcpy;
		dmu_buf_t *db = dbp[i];

		bufoff = offset - db->db_offset;
		ASSERT3S(bufoff, >=, 0);

		tocpy = MIN(db->db_size - bufoff, size);
		if (tocpy == 0)
			break;

		ASSERT(i == 0 || i == numbufs-1 || tocpy == db->db_size);

		if (tocpy == db->db_size)
			dmu_buf_will_fill(db, tx);
		else
			dmu_buf_will_dirty(db, tx);

		didcpy = dmu_bio_copy(db->db_data + bufoff, tocpy, bio,
		    bio_offset);

		if (tocpy == db->db_size)
			dmu_buf_fill_done(db, tx);

		if (didcpy < tocpy)
			err = EIO;

		if (err)
			break;

		size -= tocpy;
		offset += didcpy;
		bio_offset += didcpy;
		err = 0;
	}

	dmu_buf_rele_array(dbp, numbufs, FTAG);
	return (err);
}
```

Вернёмся к `zvol_write`.
После записи данных из `bio` необходимо сделать коммит изменений.
Это делается при помощи функции `dmu_tx_commit`.
Она освобождает захваченные объекты списках захвата
и блокировки синхронизации, позволяя транзакционной группе
перейти в стадию синхронизации.

Затем разблокируется область диска и, в случае необходимости
(если установлен флаг "forced unit access" - синхронный сброс данных)
вызывает запись изменений в ZIL.

```c
// zvol_write
	dmu_tx_commit(tx);
	zfs_range_unlock(rl);

	if ((bio->bi_rw & VDEV_REQ_FUA) ||
	    zv->zv_objset->os_sync == ZFS_SYNC_ALWAYS)
		zil_commit(zv->zv_zilog, ZVOL_OBJ);

out:
	return (error);
}
```




### Особенности реализаций транзакционных групп

TODO: описать per-cpu структуру транзакционной группы и почему была выбранна именно такая архитектура.


### Задержки транзакций (ZFS transaction delay)

NB: данный раздел присутствует в man'е к параметрам модуля zfs. Также сюда можно добавить описание работы функции `dsl_pool_need_dirty_delay`.

We delay transactions when we've determined that the backend storage isn't able to accommodate the rate of incoming writes.

If there is already a transaction waiting, we delay relative to when that transaction will finish waiting.  This way the calculated delay time is independent of the number of threads concurrently executing transactions.

If we are the only waiter, wait relative to when the transaction started, rather than the current time.  This credits the transaction for "time already served", e.g. reading indirect blocks.

The minimum time for a transaction to take is calculated as:

```
   min_time = zfs_delay_scale * (dirty - min) / (max - dirty)
   min_time is then capped at 100 milliseconds.
```

The  delay  has  two  degrees  of  freedom  that  can  be  adjusted  via  tunables.   The  percentage  of  dirty  data  at  which  we  start  to delay is defined by zfs_delay_min_dirty_percent. This should typically be at or above
zfs_vdev_async_write_active_max_dirty_percent so that we only start to delay after writing at full speed has failed to keep up with the incoming write rate. The scale of the curve is defined by zfs_delay_scale.  Roughly  speaking,
this variable determines the amount of delay at the midpoint of the curve.

```
delay
 10ms +-------------------------------------------------------------*+
      |                                                             *|
  9ms +                                                             *+
      |                                                             *|
  8ms +                                                             *+
      |                                                            * |
  7ms +                                                            * +
      |                                                            * |
  6ms +                                                            * +
      |                                                            * |
  5ms +                                                           *  +
      |                                                           *  |
  4ms +                                                           *  +
      |                                                           *  |
  3ms +                                                          *   +
      |                                                          *   |
  2ms +                                              (midpoint) *    +
      |                                                  |    **     |
  1ms +                                                  v ***       +
      |             zfs_delay_scale ---------->     ********         |
    0 +-------------------------------------*********----------------+
      0%                    <- zfs_dirty_data_max ->               100%
```


Note  that  since  the  delay is added to the outstanding time remaining on the most recent transaction, the delay is effectively the inverse of IOPS.  Here the midpoint of 500us translates to 2000 IOPS. The shape of the curve was
chosen such that small changes in the amount of accumulated dirty data in the first 3/4 of the curve yield relatively small differences in the amount of delay.

The effects can be easier to understand when the amount of delay is represented on a log scale:

```
delay
100ms +-------------------------------------------------------------++
      +                                                              +
      |                                                              |
      +                                                             *+
 10ms +                                                             *+
      +                                                           ** +
      |                                              (midpoint)  **  |
      +                                                  |     **    +
  1ms +                                                  v ****      +
      +             zfs_delay_scale ---------->        *****         +
      |                                             ****             |
      +                                          ****                +
100us +                                        **                    +
      +                                       *                      +
      |                                      *                       |
      +                                     *                        +
 10us +                                     *                        +
      +                                                              +
      |                                                              |
      +                                                              +
      +--------------------------------------------------------------+
      0%                    <- zfs_dirty_data_max ->               100%
```

Note here that only as the amount of dirty data approaches its limit does the delay start to increase rapidly. The goal of a properly tuned system should be to keep the amount of dirty data out of that range by first ensuring that the appropriate limits are set for the I/O scheduler to reach optimal throughput on the backend storage, and then by changing the value of zfs_delay_scale to increase the steepness of the curve.


