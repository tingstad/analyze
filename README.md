# analyze


## Postprocessing

### Strip groupId and version from node names

Shorter node names may be more readable.

`sed 's/"[^:]*:\([^:]*\)[^"]*"/"\1"/g'` graph.dot

### Remove edge/line widths

Sometimes, the widths are not desired.

`sed 's/\[penwidth=[0-9.]*\]//;s/penwidth=[0-9.]*,//'` graph.dot

### Filter nodes

Just remember to preserve `{` and `}`.

`egrep '[{}]|name' graph.dot`

### Append nodes or edges

Use e.g. awk or sed.

`sed '/}/i\"foo" -> "bar";\n"bar" -> "DB";'`

