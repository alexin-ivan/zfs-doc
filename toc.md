  * [ZFS](#zfs)
    * [Термины и сокращения](#Термины-и-сокращения)
    * [ZFS Label](#zfs-label)
      * [Виртуальные устройства (VDEV) и метки на них](#Виртуальные-устройства-vdev-и-метки-на-них)
      * [Конфигурация пула (ZFS Label NVList)](#Конфигурация-пула-zfs-label-nvlist)
      * [Уберблоки (Uberblocks)](#Уберблоки-uberblocks)
      * [Просмотр меток](#Просмотр-меток)
    * [Указатели на блоки (Block Pointers)](#Указатели-на-блоки-block-pointers)
      * [Косвенные блоки (indirect blkptr) и размеры блоков](#Косвенные-блоки-indirect-blkptr-и-размеры-блоков)
      * [Заполненность блоков (fill/hole)](#Заполненность-блоков-fillhole)
      * [Встраиваемый BP (embedded blkptr)](#Встраиваемый-bp-embedded-blkptr)
      * [Gang-блоки (Gang Blocks)](#gang-блоки-gang-blocks)
      * [Типы объектов ZFS](#Типы-объектов-zfs)
    * [Объекты и слой DMU](#Объекты-и-слой-dmu)
      * [MOS](#mos)
      * [Косвенные блоки и объекты](#Косвенные-блоки-и-объекты)
    * [DBUF](#dbuf)
      * [Реализация COW-механизма в DBUF](#Реализация-cow-механизма-в-dbuf)
      * [Статистика по DMU-буферам](#Статистика-по-dmu-буферам)
    * [Транзакционные группы (TXG)](#Транзакционные-группы-txg)
      * [Особенности реализаций транзакционных групп](#Особенности-реализаций-транзакционных-групп)
      * [Задержки транзакций (ZFS transaction delay)](#Задержки-транзакций-zfs-transaction-delay)
    * [SPA](#spa)
      * [Метаслабы](#Метаслабы)
      * [Вес метаслаба](#Вес-метаслаба)
      * [Методы выделения сегментов](#Методы-выделения-сегментов)
    * [VDEV](#vdev)
      * [Обобщённый интерфейс устройств VDEV](#Обобщённый-интерфейс-устройств-vdev)
      * [Особенности VDEV типа disk](#Особенности-vdev-типа-disk)
      * [Особенности VDEV типа raidz](#Особенности-vdev-типа-raidz)
    * [ARC](#arc)
      * [Особенности arc](#Особенности-arc)
      * [Особенности l2arc](#Особенности-l2arc)
      * [Особенности реализации ARC](#Особенности-реализации-arc)
    * [Журнал намерений (ZIL)](#Журнал-намерений-zil)
    * [Сбор статистики из kstat](#Сбор-статистики-из-kstat)
  * [Дополнительные материалы](#Дополнительные-материалы)
    * [space maps](#space-maps)
      * [Битовые карты](#Битовые-карты)
      * [Отложенное освобождение](#Отложенное-освобождение)
      * [Карты пространства: списки диапазонов с журнальной структурой](#Карты-пространства-списки-диапазонов-с-журнальной-структурой)