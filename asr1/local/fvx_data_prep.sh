#!/usr/bin/env bash

# Copyright  2021 FlipVox Solutions OPC (Author: Federico Ang)
# Apache 2.0

# FVX-ISIP FDC data prep v1
# 28:6:15.50 of useful data

# ISIP TGL data prep v1
# 33:29:51.82 of useful data

# Run from one directory above (i.e. local/fvx_data_prep.sh )

. ./path.sh
set -e # exit on error

# need to supply FVX-ISIP package location
# FDC processing is different with the TGL subset!
if [ $# -ne 1 ]; then
    echo "Usage: fvx_data_prep.sh <fvx-dir>"
    exit 1;
fi

#############################
# FVX-FDC: Data Preparation #_______________________

# check if FDC version is correct
if [ ! -f $1/FDC/TEXT_DATA/TRANSCRIPTIONS ]; then
    echo "Error: incorrect version of FVX-ISIP dataset!"
    exit 1;
fi

FDCLOC=$1/ISIP/FDC

# soft linking within workspace
newdir=data/raw/ISIP
mkdir -p ${newdir}
FDCDATATOP=${newdir}/FDC
rm -f ${FDCDATATOP}
ln -s ${FDCLOC} ${FDCDATATOP}

#####################
# extraction proper #
#####################

fdcdir=data/local/ISIP/FDC
rm -fr $fdcdir
mkdir -p $fdcdir

while read -r name wavfile start end trans; do

    # make folder
    targetdir=${fdcdir}/$name
    mkdir -p $targetdir
    
    echo $FDCDATATOP/$name/$wavfile".wav" >> $targetdir/${name}-wav.list
    
    duration=`soxi $FDCDATATOP/$name"/"$wavfile".wav" |\
        grep -o '[0-9][0-9]:[0-9][0-9]:[0-9][0-9]\.[0-9][0-9]' |\
        awk -F':' '{s=$3+60*$2+3600*$1; print s}'`
    # old janus-style transcriptions used -1 for until end
    if (( $(echo "$end > 0" | bc) )); then
        duration=$end
    fi
    echo | awk -v a="$wavfile" -v b=$start -v c=$duration -v d="$trans" \
        '{printf "%s-%06.0f_%06.0f\t%s\t%s\t%s\n",a,int(1000*b),int(1000*c),b,c,tolower(d)}' \
        >> $targetdir/${name}-trn.txt
        
done < <(cat $FDCDATATOP/TEXT_DATA/TRANSCRIPTIONS)

#########
# patch #
#########

# reserved for patches
# 1428_081111_055251_0314 should be pressure
# 7499_090220_110637_0168 should be <no-speech>

###########################
# kaldi-style corrections #
###########################

dir=data/isip_fdc
rm -fr $dir
mkdir -p $dir

export LC_ALL=C;

# (1a) kaldi-style manifest
cat ${fdcdir}/*/*-wav.list 2>/dev/null | sed '/^$/d' | sort --parallel=8 | uniq > $dir/wav.flist

n=`cat $dir/wav.flist | wc -l`

[ $n -ne 14300 ] && \
    echo "Warning: expected 14300 data files, found $n."

sed -e 's?.*/\([^/]*\)/\([^/]*$\)?\2?' -e 's?.wav??' $dir/wav.flist | paste - $dir/wav.flist \
    > $dir/wavflist.scp

awk '{
    printf("%s cat ", $1);
    for (i=2;i<=NF;i++) {
        printf("%s ",$i)
    }
    printf("|\n")
}' < $dir/wavflist.scp | sort --parallel=8 > $dir/wav.scp || exit 1;

# (1b) Transcriptions preparation
# make basic transcription file

awk -F'\t' '{printf "%s %s\n",$1,$4}' ${fdcdir}/*/*-trn.txt > $dir/text

# text formatting
cat $dir/text |\
    sed 's/\([a-z]\)\.\([a-z]\)\.\([a-z]\)\.\([a-z]\)\.\([a-z]\)\./\u\1_\u\2_\u\3_\u\4_\u\5_/g' |\
    sed 's/\([a-z]\)\.\([a-z]\)\.\([a-z]\)\.\([a-z]\)\./\u\1_\u\2_\u\3_\u\4_/g' |\
    sed 's/\([a-z]\)\.\([a-z]\)\.\([a-z]\)\./\u\1_\u\2_\u\3_/g' |\
    sed 's/\([a-z]\)\.\([a-z]\)\./\u\1_\u\2_/g' | sed 's/+garbage+/<int>/g' | sed 's/+breath+/<breath>/g' |\
    sed 's/dep\.ed/dep-ed/g' | sed 's/+sob+/<sob>/g' | sed 's/+bg+/<sta>/g' |\
    sed 's/+laugh+/<laugh>/g' | sed 's/+fragment+/(())/g' | sed 's/\(+umm+\|+hmm+\)/<hes>/g' |\
    sed 's/ \([a-z]\)\.$/ \u\1_/g' | LC_ALL=C.UTF-8 sed 's/ñ/~n/g' | sed 's|l/c|L_ / C_|g' |\
    sed 's/ \([a-z]\)\. / \u\1_ /g' | sed 's/ \([a-z]\)\. / \u\1_ /g' | sed 's/ \([a-z]\)\. / \u\1_ /g' |\
    sed 's/atbp\./at iba pa/g' | sed 's/abs-cbn/A_B_S_-C_B_N_/g' > $dir/text2
mv $dir/text2 $dir/text

sort --parallel=8 $dir/text > $dir/text_SORTED
mv $dir/text_SORTED $dir/text
sort -c $dir/text || exit 1;

# (1c) Make segments files from transcript
awk '{
    segment=$1
    split(segment,S,"[-]");
    spkid=S[1];
    split(S[2],ts,"[_]");
    print segment " " spkid " " ts[1]/1000 " " ts[2]/1000
}' <(cat ${fdcdir}/*/*-trn.txt) > $dir/segments

sort --parallel=8 $dir/segments > $dir/segments_SORTED
mv $dir/segments_SORTED $dir/segments
sort -c $dir/segments || exit 1;

# (1d) utt2spk
cut -d' ' -f1-2 $dir/segments > $dir/utt2spk || exit 1;
sort --parallel=8 -k2 $dir/utt2spk > $dir/utt2spk_SORTED
mv $dir/utt2spk_SORTED $dir/utt2spk

# (1e) spk2utt
sort -k 2 $dir/utt2spk | utils/utt2spk_to_spk2utt.pl > $dir/spk2utt || exit 1;

echo "FVX-ISIP FDC data preparation succeeded."

utils/fix_data_dir.sh $dir


##############################
# ISIP-TGL: Data Preparation #_______________________

# check if version is correct
if [ ! -f $1/TGL/TGL_ACRONYM_REPLACEMENTS ]; then
  echo "Error: incorrect version of FVX-ISIP dataset!"
  exit 1;
fi

TGLLOC=$1/ISIP/TGL

# soft linking within workspace
TGLDATATOP=${newdir}/TGL
rm -f ${TGLDATATOP}
ln -s ${TGLLOC} ${TGLDATATOP}

#####################
# extraction proper #
#####################

tgldir=data/local/ISIP/TGL
rm -fr $tgldir
mkdir -p $tgldir

while IFS= read -r -d '' n; do
    sample="$n"
    filname=$(basename "$sample" .log)
  
    while read -r line settype trans; do
        duration=`soxi "$(dirname "$sample")/$line" | grep -o '[0-9][0-9]:[0-9][0-9]:[0-9][0-9]\.[0-9][0-9]' |\
            awk -F':' '{s=$3+60*$2+3600*$1; print s}'`
    
        targetdir=${tgldir}/${settype}/${filname}
    
        # make folder
        mkdir -p $targetdir
        echo "$(dirname "$sample")/$line" >> $targetdir/${filname}-wav.list

        # remove invisible symbols
        trans=$(echo "$trans" | sed 's/\xc2\x96//g' | sed 's/\xc2\xa0//g' | sed 's/\xef\xbb\xbf//g' |\
                sed 's/\x09/ /g')

        # normalize acronyms for better g2p
        trans=$(echo "$trans" |\
            sed "$(echo `cat ${TGLDATATOP}/TGL_ACRONYM_REPLACEMENTS | sed 's/\([^:]*\):\([^:]*\)/s|\\\\<\1\\\\>|\2|g;/g' | tr '\012' ' '`)")

        # removal of single-quoted expressions
        trans=$(echo "$trans" | sed "s/'\([^']*\)'\([ .]\|$\)/\1\2/g")

        # separate symbols so they can be mapped to silence
        trans=$(echo "$trans" | sed 's/[!",`|~:;?\[*]/ & /g;' | sed 's/^[ ]\+//g' | sed 's/\r//g')

        # for minimum pairs recordings
        if [ "$settype" = "Iso_MinPairs" ]; then
            trans=$(echo "$trans" | sed 's/-/ <no-speech> /g' | sed 's/([^)]*$//g')
        fi

        # expand numerals
        if [ "$settype" = "Iso_Random_Digit" ]; then
            trans=$(echo "$trans" | sed "s/100/isang daan/g; s/10/sampu/g; s/17/labimpito/g;\
                    s/1$/isa/g; s/2$/dalawa/g; s/3$/tatlo/g; s/4$/apat/g; s/5$/lima/g; \
                    s/6$/anim/g; s/7$/pito/g; s/8$/walo/g; s/9$/siyam/g; \
                    s/^1/labing /g; s/^2/dalawampu't /g; s/^3/tatlumpu't /g; s/^4/apatnapu't /g; \
                    s/^5/limampu't /g; s/^6/animnapu't /g; s/^7/pitumpu't /g; s/^8/walumpu't /g; \
                    s/^9/siyamnapu't /g" | sed "s/'t 0//g" )
        fi

        # specific reading of numeral
        if [ "$filname" = "0812_110816_021250" ] || [ "$filname" = "4281_110817_051434" ] || [ "$filname" = "8125_110816_100658" ];
        then
            trans=$(echo "$trans" | sed "s/Taung 1895/taong eighteen ninety five/g")
        fi
        if [ "$filname" = "5093_110818_065955" ] || [ "$filname" = "5968_110824_005315" ];
        then
            trans=$(echo "$trans" | sed "s/Taung 1895/taong isang libo walong daan siyamnapu't lima/g")
        fi
        if [ "$filname" = "5984_110823_083245" ] || [ "$filname" = "9640_110818_005729" ];
        then
            trans=$(echo "$trans" | sed "s/Taung 1895/taong isang libo walong daan at siyamnapu't lima/g")
        fi

        echo | awk -v a="$(basename "$line" .wav)" -v b=$duration -v c="$trans" \
            '{print a"\t0.0\t"b"\t"tolower(c);}' |\
            sed 's/\xc3\xa0/a/g; s/\xc3\xa1/a/g; s/\xc3\xa2/a/g' |\
            sed 's/\xc3\xa9/e/g' |\
            sed 's/\xc3\xac/i/g; s/\xc3\xad/i/g; s/\xc3\xae/i/g;' |\
            sed 's/\xc3\xb2/o/g; s/\xc3\xb3/o/g; s/\xc3\xb4/o/g;' |\
            sed 's/\xc3\xba/u/g;' |\
            sed "s/\xe2\x80\x99/'/g" | sed 's/&/ and /g' | sed 's/\xc3\xbf//g' |\
            sed 's|/| <no-speech> |g' | sed 's/[ \t](.*)$//g' | sed 's/([^)]*)//g' | sed 's/mr\./mister/g' |\
            sed 's/\([a-z][a-z]\)\./\1 ./g' | sed 's/ [ ]*/ /g;' | sed 's/[ ]\+$//g;' |\
            sed 's/\. <no-speech>/<no-speech>/g' | sed 's/ \.[ ]\?$//g' |\
            sed "s/'s\.$/'s/g" | sed 's/\.[.]\+/./g' | LC_ALL=C.UTF-8 sed 's/ñ/~n/g' |\
            sed 's/el nino/el ni~no/g; s/los ninos/los ni~nos/g; s/la nina/la ni~na/g' |\
            sed 's/mo a\.$/mo ah/g' \
            >> $targetdir/${filname}-trn.txt
    done < <(grep '\.wav' "$sample" | sed 's/Random Digit/Iso_Random_Digit/g; s/\.txt//g; s/TGL_//g; s/"//g')

done < <(find $TGLDATATOP/* -iname "*.log" -print0)

#########
# patch #
#########

# reserved for patches

###########################
# kaldi-style corrections #
###########################

dir=data/isip_tgl
rm -fr $dir
mkdir -p $dir

export LC_ALL=C;

# (1a) kaldi-style manifest
ls ${tgldir}/*/*/*-wav.list | grep -v '[Ss]po' | xargs cat 2>/dev/null | sed '/^$/d' | sort --parallel=8 |\
    uniq > $dir/wav.flist2 
cat $dir/wav.flist2 > $dir/wav.flist

n=`cat $dir/wav.flist | wc -l`

[ $n -ne 42802 ] && \
  echo "Warning: expected 42802 data files, found $n."

sed -e 's?.*/\([^/]*\)/\([^/]*$\)?\2?' -e 's?.wav??' $dir/wav.flist2 | paste - $dir/wav.flist2 \
  > $dir/wavflist.scp

awk '{
    printf("%s cat ", $1);
    for (i=2;i<=NF;i++) {
        printf("%s ",$i)
    }
    printf("|\n")
}' < $dir/wavflist.scp | sort > $dir/wav.scp || exit 1;

# (1b) Transcriptions preparation
# make basic transcription file

ls ${tgldir}/*/*/*-trn.txt | grep -v '[Ss]po' | xargs cat 2>/dev/null | awk -F'\t' '{printf "%s  %s\n",$1,$4}' |\
    sort --parallel=8 > $dir/text

# (1c) Make segments files from transcript
# for cases where files and utts are 1-to-1, segment is same as speaker (kaldi limitation)
ls ${tgldir}/*/*/*-trn.txt | grep -v '[Ss]po' | xargs cat 2>/dev/null |\
awk '{
    segment=$1
    spkid=$1
    print segment " " spkid " " $2 " " $3
}' | sort --parallel=8 > $dir/segments

# (1d) utt2spk
cut -d' ' -f1-2 $dir/segments > $dir/utt2spk || exit 1;
sort --parallel=8 -k2 $dir/utt2spk > $dir/utt2spk_SORTED
mv $dir/utt2spk_SORTED $dir/utt2spk

# (1e) spk2utt
sort -k 2 $dir/utt2spk | utils/utt2spk_to_spk2utt.pl > $dir/spk2utt || exit 1;

echo "ISIP TGL data preparation succeeded."

utils/fix_data_dir.sh $dir

# train folder
utils/combine_data.sh data/train \
    data/isip_fdc data/isip_tgl

echo "$0: FVX-ISIP train data preparation succeeded."