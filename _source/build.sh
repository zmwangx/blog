#!/usr/bin/env zsh

here=$0:A:h
root=$here:h
template=$here/template.html
filter=$here/filter.py
for source in $here/*.md; do
    name=$source:t:r
    dest=$root/$name.html
    pandoc -f markdown -t html --template $template $source | $filter > $dest
    echo "$dest:t" >&2
done
