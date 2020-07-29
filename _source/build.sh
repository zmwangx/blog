#!/usr/bin/env zsh

[[ $1 == (-h|--help) ]] && {
    cat <<EOF
$0 [-h|--help] [-w|--watch]
EOF
    exit 1
}
[[ $1 == -w || $1 == --watch ]] && watch=1 || watch=0

here=$0:A:h
root=$here:h
template=$here/template.html
syntax_additions=(--syntax-definition=$here/syntax/toml.xml)
filter=$here/filter.py

builder="$(mktemp /tmp/blog-builder-XXXXXX)"
trap 'rm -f $builder' EXIT INT TERM
cat >$builder <<EOF
#!/usr/bin/env zsh
for source; do
    name=\$source:t:r
    dest=$root/\$name.html
    pandoc -f markdown -t html --template=$template $syntax_additions \$source | $filter > \$dest
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] \$dest:t" >&2
done
EOF
chmod +x $builder

$builder $here/*.md
(( watch )) && print -l $here/*.md | entr -p $builder /_
