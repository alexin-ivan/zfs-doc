## ZIO

### Конвейер ZIO

## VDEV

### Обобщённый интерфейс устройств VDEV

### Особенности VDEV типа disk

### Особенности VDEV типа raidz

## ARC

### Отличия ARC в ZoL от оригинального (академического) ARC

## SPA

### Принципы блокировок в SPA слое


## Отладка `ZFS`

### Сборка отладочной версии `ZFS`

### Утилита `zdb`

### Содержимое `/proc/spl`


## to delete

### Как получить `dnode`?

```
dnode_hold(metanode, object) -> dnode_hold_impl(os, object) -> 
{ blkid (offset) = which_blk(os->meta, object); dbuf_hold(meta, blk); } -> dbuf_hold_impl -> __dbuf_hold_impl ->
{ dbuf = dbuf_find(os, object, level, blkid); -> dbuf = dbuf_hash_table[(os, obj, lvl, blkid)]; } ->
{ while dbuf has not data then walk to parent and create new dbuf } ->
```


