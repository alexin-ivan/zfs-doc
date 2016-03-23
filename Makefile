SDATE=current
SRC=report.md
BOOK=/tmp/book.md
OUT_DIR=$(PWD)
OUT_PDF=$(OUT_DIR)/report.pdf
OUT_ODT=$(OUT_DIR)/report.odt
OUT_HTML=$(OUT_DIR)/index.html
imgs:=$(ls ./img/*)

FILTER_SVG=--filter=./filters/pandoc_svg.py 
FILTER_REFS=--filter ./filters/pandoc_fignos.py --filter ./filters/pandoc_tablenos.py
USE_TOC=--toc
HTML_TPL=--template ./tpl/template.html --css ./tpl/template.css
USE_FILTER=$(FILTER_REFS)

LATEX_ENGINE=--latex-engine=xelatex

VAR_LANG=-V lang=russian
VAR_BABEL_LANG=-V babel-russian
VAR_MAINFONT=-V mainfont="Ubuntu"
VAR_MONOFONT=-V monofont="Droid Sans Mono"
VARS=$(VAR_LANG) $(VAR_BABEL_LANG) $(VAR_MAINFONT) $(VAR_MONOFONT)

CHAPTERS=\
	 zfs.md \
	 terms.md \
	 zfs-label.md \
	 zfs-bp.md \
	 zfs-dmu.md \
	 zfs-dbuf.md \
	 zfs-txg.md \
	 zfs-spa.md \
	 zfs-vdev.md \
	 zfs-arc.md \
	 zfs-zil.md \
	 zfs-kstat.md \
	 appendix.md \
	 zfs-space_maps.md

TOC=toc.md

all: $(OUT_HTML) $(img)

$(SRC): $(TOC) $(CHAPTERS)
	cat $(TOC) $(CHAPTERS) > $(SRC)

$(BOOK): $(TOC) $(CHAPTERS)
	cat $(CHAPTERS) > $(BOOK)

$(OUT_PDF): $(OUT_DIR) $(BOOK)
	pandoc $(USE_TOC) -o $(OUT_PDF) $(USE_FILTER) $(LATEX_ENGINE) $(VARS) $(BOOK)

pdf: $(OUT_PDF)

html: $(OUT_HTML)

odt: $(OUT_ODT)

$(OUT_ODT): $(OUT_DIR) $(BOOK)
	pandoc $(USE_TOC) $(BOOK) -o $(OUT_ODT) $(USE_FILTER) -V lang=russian -V babel-lang=russian $(VARS)

$(OUT_HTML): $(OUT_DIR) $(BOOK)
	pandoc $(USE_TOC) -t html5 --self-contained -o $(OUT_HTML) $(USE_FILTER) $(HTML_TPL) $(VARS) $(BOOK)

open: $(OUT_PDF)
	xdg-open $(OUT_PDF)

$(TOC): $(CHAPTERS)
	cat $(CHAPTERS) | gh-md-toc - > $(TOC)

genmake:
	echo '$$SDATE='"$(SDATE)" > ../$(SDATE)/Makefile
	cat ./Makefile >> ../$(SDATE)/Makefile
	
$(OUT_DIR):
	@if test -d $@ ; then true; else mkdir $@; fi

pre_build:
	pip install pandoc-fignos
	pip install pandoc-tablenos
	pip install pandoc-eqnos

pre_python:
	@bash -c 'echo -en "Do:\n\tpyenv shell 2.7.9\n"'

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
	rm -fR $(OUT_HTML)

edit: $(OUT_DIR)
	gvim $(SRC)
