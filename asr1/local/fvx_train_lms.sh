#!/bin/bash 

# Copyright 2013  Arnab Ghoshal
#                 Johns Hopkins University (author: Daniel Povey)
# Modified  2021  FlipVox Solutions OPC (author: Federico Ang)
# slightly changed for FlipVox kaldi recipe

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION ANY IMPLIED
# WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR PURPOSE,
# MERCHANTABLITY OR NON-INFRINGEMENT.
# See the Apache 2 License for the specific language governing permissions and
# limitations under the License.

# To be run from one directory above this script.

help_message="Usage: "`basename $0`" [options] <train-txt> <dict> <out-dir>
Train language models for FVX.\n
options: 
  --help          # print this message and exit
";

. utils/parse_options.sh

if [ $# -ne 3 ]; then
  printf "$help_message\n";
  exit 1;
fi

text=$1    
lexicon=$2 
dir=$3     
. ./path.sh

for f in "$text" "$lexicon"; do
  [ ! -f $x ] && echo "$0: No such file $f" && exit 1;
done

loc=`which ngram-count`;
if [ -z $loc ]; then
  if uname -a | grep 64 >/dev/null; then # some kind of 64 bit...
    sdir=${KALDI_ROOT}/tools/srilm/bin/i686-m64 
  else
    sdir=${KALDI_ROOT}/tools/srilm/bin/i686
  fi
  if [ -f $sdir/ngram-count ]; then
    echo Using SRILM tools from $sdir
    export PATH=$PATH:$sdir
  else
    echo You appear to not have SRILM tools installed, either on your path,
    echo or installed in $sdir.  See tools/install_srilm.sh for installation
    echo instructions.
    exit 1
  fi
fi
    

set -o errexit
rm -fr $dir/tmp
mkdir -p $dir/tmp
export LC_ALL=C

holdout=10000
shuf $text > $dir/tmp/shuftxt
cut -d' ' -f2- $dir/tmp/shuftxt | gzip -c > $dir/tmp/train.all.gz
cut -d' ' -f2- $dir/tmp/shuftxt | tail -n +$[holdout + 1] | gzip -c > $dir/tmp/train.gz
cut -d' ' -f2- $dir/tmp/shuftxt | head -n $holdout > $dir/tmp/holdout

cut -d' ' -f1 $lexicon > $dir/wordlist

for order in 3 4; do
    ngram-count -text $dir/tmp/train.all.gz -order ${order} -limit-vocab -vocab $dir/wordlist \
        -unk -map-unk "(())" -kndiscount -interpolate -lm $dir/fvx.o${order}g.kn.gz
    ngram-count -text $dir/tmp/train.gz -order $order -limit-vocab -vocab $dir/wordlist \
        -unk -map-unk "(())" -kndiscount -interpolate -lm $dir/tmp/fvx.o${order}g.kn.gz
    echo "PPL for FVX ${order}-gram LM:"
    ngram -unk -map-unk "(())" -lm $dir/tmp/fvx.o${order}g.kn.gz -ppl $dir/tmp/holdout
    ngram -unk -map-unk "(())" -lm $dir/tmp/fvx.o${order}g.kn.gz -ppl $dir/tmp/holdout -debug 2 >& $dir/tmp/fvx.o${order}g.kn.ppl
#   PPL for FVX 3-gram LM:
#       file data/local/lm/tmp/holdout: 10000 sentences, 78023 words, 0 OOVs
#       0 zeroprobs, logprob= -113899.5 ppl= 19.67772 ppl1= 28.82836
#   PPL for FVX 4-gram LM:
#       file data/local/lm/tmp/holdout: 10000 sentences, 78023 words, 0 OOVs
#       0 zeroprobs, logprob= -167505.1 ppl= 79.97794 ppl1= 140.239
done
