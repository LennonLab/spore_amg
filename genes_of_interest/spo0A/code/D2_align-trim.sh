#!/bin/bash

#This was executed on Carbonate interactive job

#Interactive job on Carbonate
srun -p interactive -N 1 --ntasks-per-node=1 --cpus-per-task=8 --time=07:59:00 --pty bash

#### load dependencies ####

# local dependencies #
TOOLS=/N/u/danschw/Carbonate/my_tools
MAFFT=${TOOLS}/mafft-7.490-without-extensions/bin
# MAFFT v7.475 (2020/Nov/23)Breezin
# MBE 30:772-780 (2013), NAR 30:3059-3066 (2002)
# https://mafft.cbrc.jp/alignment/software/

TRIMAL=/geode2/home/u020/danschw/Carbonate/my_tools/trimal-trimAl/source
# trimAl v1.4.rev22 build[2015-05-21]. 2009-2015. Salvador Capella-Gutierrez and Toni Gabaldón.
# trimAl webpage: http://trimal.cgenomics.org
# (used in Consuelo Gazitúa wt (2020) paper (Sullivan lab))


##### Define paths #####
PARENT=~/GitHub/spore_amg/genes_of_interest/spo0A
ODIR=${PARENT}/data/align-trim-tree
mkdir -p ${ODIR}


# alignment
cd $MAFFT

./mafft-einsi  --thread 8 ${PARENT}/data/seq2align.faa > ${ODIR}/seq2align_MafftEinsi.aln

# trim alignment
cd $TRIMAL

./trimal -in ${ODIR}/seq2align_MafftEinsi.aln -out ${ODIR}/seq2align_MafftEinsi.trim -gappyout

head ${ODIR}/seq2align_MafftEinsi.aln
