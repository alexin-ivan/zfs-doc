SDATE=current
SRC=report.md
OUT_DIR=$(PWD)
OUT_PDF=$(OUT_DIR)/report.pdf
OUT_ODT=$(OUT_DIR)/report.odt
imgs:=$(ls ./img/*)

FILTER=--filter=$(HOME)/local/share/python/pandoc-svg.py
TOC=--toc
USE_FILTER= #$(FILTER)
FIRST_CHAP='# ZFS'

all: $(OUT_PDF) $(img)

$(OUT_PDF): $(OUT_DIR) $(SRC)
	cat $(SRC) | sed -n -e '/# ZFS/,$$p' | pandoc $(TOC) -o $(OUT_PDF) $(USE_FILTER) -V lang=russian -V babel-lang=russian --latex-engine=xelatex -V mainfont="Ubuntu"

pdf: $(OUT_PDF)

odt: $(OUT_DIR) $(SRC)
	pandoc $(TOC) $(SRC) -o $(OUT_ODT) $(USE_FILTER) -V lang=russian -V babel-lang=russian -V mainfont="Ubuntu"

open: $(OUT_PDF)
	xdg-open $(OUT_PDF)


genmake:
	echo '$$SDATE='"$(SDATE)" > ../$(SDATE)/Makefile
	cat ./Makefile >> ../$(SDATE)/Makefile
	
$(OUT_DIR):
	@if test -d $@ ; then true; else mkdir $@; fi

clean:
	rm -fR *.aux
	rm -fR *.log
	rm -fR *.bcf
	rm -fR *.out
	rm -fR *.toc
	rm -fR *.run.xml
	rm -fR *.toc
	rm -fR $(OUT_PDF)
	rm -fR $(OUT_ODT)

edit: $(OUT_DIR)
	gvim $(SRC)
