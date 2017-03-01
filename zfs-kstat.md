## Сбор статистики из kstat

Подсистема `kstat` предназначена для сбора различной статистики о `ZFS`
и представления её пользователю.

`kstat` является частью `SPL` (`Solaris Porting Layer`) и адаптирована для `linux`.

Файлы `kstat` хранятся в директории `/proc/spl/kstat`.

Рассмотрим некоторые из них.

1. `/proc/spl/kstat/<pool>/dmu_tx_assign`
Статистика (гистограмма) скорости добавления транзакций в группы.
Позволяет оценить нагрузку на пул `ZFS`: чем больше транзакций
присваивается с большей задержкой, тем нагрузка выше.

```conf
#cat /proc/spl/kstat/zfs/tank/dmu_tx_assign 
451 1 0x01 32 1536 1451698481637227 1454383185424447
name                            type data
1 ns                            4    0
2 ns                            4    0
4 ns                            4    0
8 ns                            4    0
16 ns                           4    0
32 ns                           4    0
64 ns                           4    0
128 ns                          4    4195
256 ns                          4    1417
512 ns                          4    965
1024 ns                         4    74
2048 ns                         4    17
4096 ns                         4    0
8192 ns                         4    0
16384 ns                        4    9
32768 ns                        4    27
65536 ns                        4    432
131072 ns                       4    23578
262144 ns                       4    65034
524288 ns                       4    98741
1048576 ns                      4    2232869
2097152 ns                      4    410628
4194304 ns                      4    526712
8388608 ns                      4    1826
16777216 ns                     4    224
33554432 ns                     4    98
67108864 ns                     4    45
134217728 ns                    4    39
268435456 ns                    4    17
536870912 ns                    4    1
1073741824 ns                   4    0
2147483648 ns                   4    111
```

2. `/proc/spl/kstat/zfs/dbufs`
"Сырая" статистика по DMU-буферам. Более "читабельную" версию можно получить
с помощью скрипта `dbufstat.py`:

```conf
           pool  objset      object                        dtype  cached
          tank        0           0                 DMU_OT_DNODE     96K
          tank        0          31                 DMU_OT_BPOBJ     16K
          tank        0         105             DMU_OT_SPACE_MAP     16K
          tank       21           9   DMU_OT_PLAIN_FILE_CONTENTS     12G
          tank       21           8   DMU_OT_PLAIN_FILE_CONTENTS     12G
          tank       21           7   DMU_OT_PLAIN_FILE_CONTENTS     14G
          tank       21           0                 DMU_OT_DNODE    112K
```

3. `/proc/spl/kstat/<pool>/io`
Статистика ввода вывода. Выводит информацию о том, сколько операций доступа и какое количество
данных было проведено для пула.
Стоит отмерить разницу в выводе `zpool list`, `zpool list -v` и `kstat/<pool>/io`.

`zpool list <pool>` выводит информацию о ZIO операциях с корневым `vdev`.

`zpool list -v <pool>` выводит детальную информацию о ZIO операциях по дочерним `vdev`.

`kstat/<pool>/io` выводит информацию по коневому `vdev`.

Таким образом, к примеру, в случае `raidz`, в корневом `vdev` будет отображаться одна операция записи,
а у дочерних - несколько. Соответственно, сумма "скоростей" записи на физические диски будет меньше,
чем "скорость" записи на пул, т.к. будет "оверхед", связанный с избыточностью.

Кроме того, в данной статистике присутствуют следующие поля:

```c
hrtime_t   wtime;            /* cumulative wait (pre-service) time */
hrtime_t   wlentime;         /* cumulative wait length*time product*/
hrtime_t   wlastupdate;      /* last time wait queue changed */
hrtime_t   rtime;            /* cumulative run (service) time */
hrtime_t   rlentime;         /* cumulative run length*time product */
hrtime_t   rlastupdate;      /* last time run queue changed */
uint_t     wcnt;             /* count of elements in wait state */
uint_t     rcnt;             /* count of elements in run state */
```

Они связаны с длинной очереди входных данных на vdev'ы.

