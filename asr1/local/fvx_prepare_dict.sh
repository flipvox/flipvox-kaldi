#!/usr/bin/env bash

# Derive base lexicon from FVXdict
# Prepare dict_nosilp/ from lexicon.txt

. ./path.sh
set -e # exit on error

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <lexicon> <dict_dir>"
  exit 1
fi

lexicon=$1
dir=$2

# download FVXdict
dict_src=$(dirname ${lexicon})
rm -fr ${dict_src}
git clone https://github.com/flipvox/FVXdict.git ${dict_src}

# create base dictionary by
# combining core and noncore
# setting all entries to lowercase (except initialisms)
# removing tab
# resetting enye symbol to ~n
# sorting and uniq
cat ${dict_src}/*.txt | sed '/^;;; #/d' | sed '/^[ \t]*$/d' > ${dict_src}/lexicon.txt
cut -f1 ${dict_src}/lexicon.txt | LC_ALL=C.UTF-8 tr "[:upper:]" "[:lower:]" | sed 's/\([a-z]\)_/\u\1_/g' | sed 's/ñ/~n/g' > ${dict_src}/left.txt
cut -f2- ${dict_src}/lexicon.txt > ${dict_src}/right.txt
paste -d' ' ${dict_src}/left.txt ${dict_src}/right.txt | LC_ALL=C sort --parallel=8 | uniq > ${lexicon}

mkdir -p $dir

cat $lexicon |
  awk '{ for(n=2;n<=NF;n++){ phones[$n] = 1; }} END{for (p in phones) print p;}' |
  grep -v "\(SIL\|BGN\|FLL\|SPN\|NSP\|LAU\|VOC\|SOB\)" >$dir/nonsilence_phones.txt || exit 1

# they're being designated as "silence", relative to the intended phones
( echo SIL; echo BGN; echo SPN; echo NSP; echo LAU; echo VOC; echo SOB ) > $dir/silence_phones.txt

# only one is expected here (map unwanted or spurious symbols to this)
( echo SIL; ) > $dir/optional_silence.txt

# No "extra questions" in the input to this setup, as we don't
# have stress or tone.
#echo -n >$dir/extra_questions.txt

# A few extra questions that will be added to those obtained by automatically clustering
# the "real" phones.  These ask about stress; there's also one for silence.
cat $dir/silence_phones.txt| awk '{printf("%s ", $1);} END{printf "\n";}' > $dir/extra_questions.txt || exit 1;
cat $dir/nonsilence_phones.txt | perl -e 'while(<>){ foreach $p (split(" ", $_)) {
  $p =~ m:^([^\d]+)(\d*)$: || die "Bad phone $_"; $q{$2} .= "$p "; } } foreach $l (values %q) {print "$l\n";}' \
 >> $dir/extra_questions.txt || exit 1;

# Add to the lexicon the silences, noises etc.
(
echo '<breath> SPN'
echo '<click> NSP'
echo '<cough> SPN'
echo '<dtmf> NSP'
echo '<foreign> VOC'
echo '<hes> FLL'
echo '<int> NSP'
echo '<laugh> LAU'
echo '<lipsmack> SPN'
echo '<no-speech> SIL'
echo '<overlap> VOC'
echo '<ring> NSP'
echo '<sob> SOB'
echo '<sta> BGN'
echo '<music> BGN'
echo '(()) VOC'
echo '~ VOC'
echo '-- SIL'
echo '! SIL'
echo '? SIL'
echo ', SIL'
echo '. SIL'
echo ': SIL'
echo '; SIL'
) | cat - $lexicon > $dir/lexicon.txt || exit 1

sort $dir/lexicon.txt -uo $dir/lexicon.txt

echo "$0: Done preparing $dir"
