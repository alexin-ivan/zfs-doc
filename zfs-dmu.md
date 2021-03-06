## Объекты и слой DMU

В данном пункте будут подробно рассмотрены объекты `ZFS`, т.к. они составляют большую часть системы
и являются абстракцией, упрощающей работу с `BP`.

Основной структурой, связанной с объектами является `dnode`, которая представлена в `OnDisk`-формате в виде `dnode_phys`.
Рассмотрим её основные поля:

* `dn_type`: тип объекта, с которым связана данная DN (`dmu_object_type_t`);

* `dn_indblkshift`: log2 от `indirect block size` - размера косвенных блоков;

* `dn_nlevels`: число уровней косвенности. Если 1, то `dn_blkptr` указывает на блоки данных;

* `dn_nblkptr`: длина поля dn_nblkptr (точнее - количество задействованных указателей). Значения - от 1 до 3;

* `dn_bonustype`: тип данных в bonus-буффере;

* `dn_checksum`: тип контрольной суммы (`enum zio_checksum`);

* `dn_compress`: тип сжатия (`enum zio_compress`);

* `dn_flags`: флаги
	- `DNODE_FLAG_USED_BYTES (1<<0)`: dn_used использует байты? если нет, то `dn_used` в качестве единиц использует `SPA_MINBLOCKSIZE` (512b)
	- `DNODE_FLAG_USERUSED_ACCOUNTED (1<<1)`
	- `DNODE_FLAG_SPILL_BLKPTR (1<<2)`: имеет ли данный объект системные аттрибуты в bonus-буффере

* `dn_datablkszsec`: размер блока данных в 512b секторах;

* `dn_bonuslen`: длина dn_bonus (bonus-буффер в объединении dn_nblkptr);

* `dn_pad2[4]`: зарезервировано/дополнение для выравнивания

* `dn_maxblkid`: наибольший ID выделенного блока

* `dn_used`: объём используемого дискового пространства (в байтах или секторах в зависимости от `dn_flags`)

* `dn_pad3[4]`: зарезервировано/дополнение для выравнивания

* `dn_blkptr`: объединение, которое может использоваться тремя различными способами:
```
0       64      128     192     256     320     384     448 (offset)
+---------------+---------------+---------------+-------+
| dn_blkptr[0]  | dn_blkptr[1]  | dn_blkptr[2]  | /     |
+---------------+---------------+---------------+-------+
| dn_blkptr[0]  | dn_bonus[0..319]                      |
+---------------+-----------------------+---------------+
| dn_blkptr[0]  | /                     | dn_spill      |
+---------------+-----------------------+---------------+
```

### MOS

Meta Objset пула - метаобъект (контейнер объектов) пула, в котором содержится
дополнительная информация о конфигурации пула, директории датасетов (DSL directory), карты датасетов (DSL child map),
метаобъекты датасетов (Dataset), метаслабы, карты пространств и другие виды объектов.
Пример получения доступа к датасету:
`MOS -> object=1.root_dataset -> ... linked list ... -> DSL directory (parent) -> DSL directory (child) -> "DSL dataset".bp -> Dataset`


### Косвенные блоки и объекты

dnode предоставляет механизмы работы с косвенными блоками. Рассмотрим датасет типа ZVOL.
После создания он состоит из следующих компонентов:

* Meta Node (можно получить через макрос `DMU_META_DNODE(objset)`), номер объекта равен 0;

* `ZVOL`-объект, номер объекта равен 1;

* `ZVOL_PROP`-объект, номер объекта равен 2;

Рассмотрим объект `Meta Node`. Данный объект представляет собой дерево из $levels$ уровней.
Значение $levels = lvl$ должно удовлетворять следующему условию:

$$ nblkptr * 2 ^ {(datablkshift + (lvl - 1) * (indblkshift - BPSHIFT))} >= MAX\_OBJECT * size_{dnode} $$, где 

* `nblkptr`, `datashift`, `indblkshift` - соответствующие поля структуры `dnode`;

* `BPSHIFT (SPA_BLKPTRSHIFT)` - размер структуры blkptr_t (128b);

* `MAX_OBJECT (DN_MAX_OBJECT)` - максимальный размер объекта ($2 ^ {48}$ байт);

* $size_{dnode}$ - размер структуры `dnode_phys` в байтах;

Если выполнить преобразования:

* Размер блока данных в байтах: $blksize = 2 ^ {datablkshift}$;

* Количество BP, которые можно разместить в одном косвенном блоке: $ind\_per\_bp = {(2 ^ {ind}) / (2 ^ {BPSHIFT})}$;

* Максимальный размер объекта, состоящего из `dnode_phys` в байтах: $max\_obj = MAX\_OBJECT * size_{dnode}$;

То получим:

$$ nblkptr * blksize *  ind\_per\_bp ^ {lvl-1} >= max\_obj$$

Учитывая, что количество элементов в дереве на глубине $lvl$ равно $ind\_per\_bp ^ {lvl}$,
то неравенство отражает тот факт, дерево должно быть достаточной глубины, для того, чтобы
вместить в себя метаобъект максимально возможного размера.
Например, `dnode`, в котором `levels = 3` и `dn_nblkptr = 2` может оперировать с объектом, 
который состоит из $2 * 128 ^ {3 - 1}$ блоков (128 - количество косвенных блоков, умещающихся на одном уровне).

`MetaNode` (объект с нулевым индексом) содержит в себе все объекты датасета. 
В случае `ZVOL`-датасета, там хранятся два объекта `DMU_OT_ZVOL` и `DMU_OT_ZVOL_PROP`.

В объекте `DMU_OT_ZVOL` также могут использоваться косвенные блоки.

Важно отметить, что в объекте `MetaNode` хранится дерево, состоящее из `dnode_phys`,
а в качестве ссылок на узлы используются указатели `dnode_phys.dn_blkptr`.
А в объекте типа `ZVOL` дерево состоит только из `blkptr_t`, 
в качестве ссылок там используются `DVA` (см. рис. 8).

Рассмотрим алгоритм обхода косвенных блоков (из zdb.c):

```c

void traverse_indirect(int objset, int object, int level, int blkid, bp) {
	// level: N
	// objset:  number in parent MetaNode object tree
	// bp:  current bp with level = L(N)
	blkptr_t *cbp; // child bp with level = L(N - 1)

	do_something(bp);

	if (BP_GET_LEVEL(bp) > 0 && !BP_IS_HOLE(bp)) {
		arc_buf_t *buf;
		// element per block = bp.lsize / sizeof(bp)
		int epb = BP_GET_LSIZE(bp) >> SPA_BLKPTRSHIFT; 
		buf = arc_read(bp); //pseudo-code
		for(i = 0; i < epb; i++, cbp++)
		{
			traverse_indirect(
				objset, 
				object, 
				level - 1, 
				blkid * epb + i, 
				cbp
			);
		}
		
	}

}
```

На рис. 9 изображено дерево, из которого состоит объект `DMU_OT_DNODE`. Если сравнить его с деревом blkptr (рис. 8),
то заметно два отличия: корень и листья в метаобъекте являются элементами `dnode_phys`.
На корень этого дерева указывает объект типа dataset из метаданных пула. А листья - указывают на объекты (метаданные) самого датасета.

![Структура мета-объекта (9)](./img/zfs-metaobject-tree.png "Структура мета-объекта (9)")


