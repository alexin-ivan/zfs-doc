SDATE=current
SRC=report.md
OUT_DIR=$(PWD)
OUT_PDF=$(OUT_DIR)/report.pdf
OUT_ODT=$(OUT_DIR)/report.odt
OUT_HTML=$(OUT_DIR)/report.html
imgs:=$(ls ./img/*)

FILTER=--filter=$(HOME)/local/share/python/pandoc-svg.py
TOC=--toc
USE_FILTER= #$(FILTER)
FIRST_CHAP='# ZFS'

LATEX_ENGINE=--latex-engine=xelatex

VAR_LANG=-V lang=russian
VAR_BABEL_LANG=-V babel-russian
VAR_MAINFONT=-V mainfont="Ubuntu"
VAR_MONOFONT=-V monofont="Droid Sans Mono"
VARS=$(VAR_LANG) $(VAR_BABEL_LANG) $(VAR_MAINFONT) $(VAR_MONOFONT)

all: $(OUT_HTML) $(img)

$(OUT_PDF): $(OUT_DIR) $(SRC)
	cat $(SRC) | sed -n -e '/# ZFS/,$$p' | pandoc $(TOC) -o $(OUT_PDF) $(USE_FILTER) $(LATEX_ENGINE) $(VARS)

pdf: $(OUT_PDF)

html: $(OUT_HTML)

odt: $(OUT_ODT)

$(OUT_ODT): $(OUT_DIR) $(SRC)
	pandoc $(TOC) $(SRC) -o $(OUT_ODT) $(USE_FILTER) -V lang=russian -V babel-lang=russian $(VARS)

$(OUT_HTML): $(OUT_DIR) $(SRC)
	cat $(SRC) | sed -n -e '/# ZFS/,$$p' | pandoc $(TOC) -t html5 --self-contained -o $(OUT_HTML) $(USE_FILTER) $(VARS)

open: $(OUT_PDF)
	xdg-open $(OUT_PDF)

gentoc:
	cat $(SRC) | gh-md-toc -

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
