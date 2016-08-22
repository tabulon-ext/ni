#!/bin/bash
# Builds the core ni image from the files in src/.
cd $(dirname $0)

# Preprocessor to erase SDoc documentation. This minimizes the image size but
# still makes it possible to document code in some detail.
unsdoc() {
  perl -e 'print join "", map s/^c\n//r,
                          grep !/^\h*[|A-Z]/,
                          split /\n(\h*\n)+/, join "", <>'
}

# Resource format is "<nlines> <filename>\n<data...>", e.g.
#
# 5 foo.pl
# #!/usr/bin/env perl
# # stuff
# while (<>) {
#   print "hi $_";
# }
#
# See src/ni for the logic that parses this from the __DATA__ section.
resource() {
  cd gen
  for r; do
    wc -l $r
    cat $r
  done
  cd ..
}

unquote() {
  for f; do
    cat "gen/$f"
  done
}

lib() {
  for l; do
    resource $l/lib
    for f in $(< src/$l/lib); do
      resource $l/$f
    done
  done
}

# SDoc-process all source files into corresponding entries in gen/.
rm -rf gen
mkdir -p gen
for f in $(find src -type f); do
  if [[ "${f%.sdoc}" != $f ]]; then
    sdoc_gen=${f%.sdoc}
    sdoc_gen=gen/${sdoc_gen#src/}
    mkdir -p $(dirname $sdoc_gen)
    unsdoc < $f > $sdoc_gen
  else
    mkdir -p gen/$(dirname ${f#src/})
    perl -npe 'chomp; $_ .= "\n"' < $f > gen/${f#src/}
  fi
done

# Build the ni image by including the header verbatim, then bundling the rest
# of the files as resources. The header knows how to unpack resources from the
# __DATA__ section of the script, and it evaluates the ones ending in .pl. This
# mechanism makes it possible for ni to serialize its code without being stored
# anywhere (which is useful if you're piping it to a system whose filesystem is
# read-only).
source gen/ni.map > ni

chmod +x ni

wc -c ni
