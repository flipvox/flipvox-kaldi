#!/usr/bin/env bash

# Copyright  2021 FlipVox Solutions OPC (Author: Federico Ang)
# Apache 2.0

# This is a shell script, but it's recommended that you run the commands one by
# one by copying and pasting into the shell (or by using the --stage flag).
# Caution: some of the graph creation steps use quite a bit of memory, so you
# should run this on a machine that has sufficient memory.

. cmd.sh
. path.sh
set -e

nj=80
nj_fmllr=20
nj_decode=80

stage=0
dnn_stage=0

dev_set=""
test_sets=""
trn_lang_name="lang_trn_3g"
test_lang_names="lang_fvx_3g"
mega_lm_name="mega_200Kvocab_p1e-8"

# options to include additional testing dataset & LMs
include_babel=false
include_mega_lms=true

. utils/parse_options.sh

# WARNING #________________________________________
# need to set these before running these scripts! #
FVX_DATA_ROOT=

if ${include_babel}; then
    echo "$0: not implemented yet!"
fi

if ${include_mega_lms}; then
    test_lang_names="${test_lang_names} lang_nosp_${mega_lm_name}_3g"
fi

#############################
# Stage 0: Data Preparation #______________________________________
if [[ ${stage} -eq 0 ]]; then

    # Prepare train set
    local/fvx_data_prep.sh ${FVX_DATA_ROOT}

    local/fvx_prepare_dict.sh data/local/dict_src/lexicon.txt \
        data/local/dict_nosilp

    utils/prepare_lang.sh --num-sil-states 4 data/local/dict_nosilp "(())" data/lang_nosilp/tmp data/lang_nosilp

    # LMs
    local/fvx_train_lms.sh \
        data/train/text data/local/dict_nosilp/lexicon.txt data/local/lm

    # LM graph
    srilm_opts="-subset -prune-lowprobs -unk -map-unk (()) -order 3"
    LM=data/local/lm/fvx.o3g.kn.gz
    utils/format_lm_sri.sh --srilm-opts "$srilm_opts" \
        data/lang_nosilp $LM data/local/dict_nosilp/lexicon.txt data/lang_nosilp_trn_3g

    for dir_name in train ${test_sets} ${dev_set}; do
        steps/make_mfcc.sh --nj ${nj} data/${dir_name}
        steps/compute_cmvn_stats.sh data/${dir_name}
        utils/validate_data_dir.sh data/${dir_name}
    done
    
    # create shortest subset using the average text length instead of specifying a count
    # setting divisor to 3 gives 3:55:59.64
    avglen=$(cat data/train/segments | awk '{print $4-$3}' | awk '{a += $0;} END {print a/NR}')
    cat data/train/segments | awk -vavglen=$avglen '{if ($4-$3 < avglen/3) print $1}' > data/shortests
    utils/subset_data_dir.sh --utt-list data/shortests data/train data/train_short
    rm data/shortests

fi

###############################
# Stage 1: Monophone training #______________________________________
if [[ ${stage} -eq 1 ]]; then
    # mono
    steps/train_mono.sh --nj ${nj} --cmd "$train_cmd" \
        data/train_short data/lang_nosilp \
        exp/mono
fi

################################
# Stage 2: TriPhone training 1 #______________________________________
if [[ ${stage} -eq 2 ]]; then
    # tri1
    steps/align_si.sh --nj ${nj} --cmd "$train_cmd" \
        data/train data/lang_nosilp exp/mono \
        exp/mono_ali

    steps/train_deltas.sh --cmd "$train_cmd" 3200 30000 \
        data/train data/lang_nosilp exp/mono_ali \
        exp/tri1
fi

################################
# Stage 3: TriPhone training 2 #______________________________________
if [[ ${stage} -eq 3 ]]; then
    # tri2
    steps/align_si.sh --nj ${nj} --cmd "$train_cmd" \
        data/train data/lang_nosilp exp/tri1 \
        exp/tri1_ali

    steps/train_deltas.sh --cmd "$train_cmd" \
        4000 70000 data/train data/lang_nosilp exp/tri1_ali \
        exp/tri2
fi

################################
# Stage 4: LDA + MLLT Training #______________________________________
if [[ ${stage} -eq 4 ]]; then
  # tri3
  # From now, we start with the LDA+MLLT system
  steps/align_si.sh --nj ${nj} --cmd "$train_cmd" \
    data/train data/lang_nosilp exp/tri2 \
    exp/tri2_ali

  # Do LDA+MLLT training, on all the data.
  steps/train_lda_mllt.sh --cmd "$train_cmd" 6000 140000 \
    data/train data/lang_nosilp exp/tri2_ali \
    exp/tri3
fi

##################################
# Stage 5: Silence probabilities #______________________________________
if [[ ${stage} -eq 5 ]]; then
    # Now we compute the pronunciation and silence probabilities from training data,
    # and re-create the lang directory.
    steps/get_prons.sh --cmd "$train_cmd" \
        data/train data/lang_nosilp exp/tri3
    utils/dict_dir_add_pronprobs.sh --max-normalize true \
        data/local/dict_nosilp exp/tri3/pron_counts_nowb.txt exp/tri3/sil_counts_nowb.txt \
        exp/tri3/pron_bigram_counts_nowb.txt data/local/dict

    utils/prepare_lang.sh data/local/dict "(())" data/local/lang data/lang
    LM=data/local/lm/fvx.o3g.kn.gz
    srilm_opts="-subset -prune-lowprobs -unk -map-unk (()) -order 3"
    utils/format_lm_sri.sh --srilm-opts "$srilm_opts" \
        data/lang $LM data/local/dict/lexicon.txt data/lang_trn_3g
fi

##################################
# Stage 6: LDA+MLLT+SAT Training #______________________________________
if [[ ${stage} -eq 6 ]]; then
    # Train tri4, which is LDA+MLLT+SAT, on all the data.
    steps/align_fmllr.sh --nj ${nj} --cmd "$train_cmd" \
        data/train data/lang exp/tri3 \
        exp/tri3_ali

    steps/train_sat.sh --cmd "$train_cmd" 11500 200000 \
        data/train data/lang exp/tri3_ali \
        exp/tri4
fi
