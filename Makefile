SDATE=current
SRC=../$(SDATE)/report.md
OUT_PDF=../$(SDATE)/report.pdf
OUT_ODT=../$(SDATE)/report.odt
OUT_DIR=../$(SDATE)
imgs:=$(ls ./img/*)

FILTER=--filter=$(HOME)/local/share/python/pandoc-svg.py
USE_FILTER= #$(FILTER)

all: $(OUT_PDF) $(img)

$(OUT_PDF): $(OUT_DIR) $(SRC)
	cd ../$(SDATE) && pandoc --toc $(SRC) -o $(OUT_PDF) $(USE_FILTER) -V lang=russian -V babel-lang=russian --latex-engine=xelatex -V mainfont="Ubuntu"

pdf: $(OUT_PDF)

odt: $(OUT_DIR) $(SRC)
	cd ../$(SDATE) && pandoc --toc $(SRC) -o $(OUT_ODT) $(USE_FILTER) -V lang=russian -V babel-lang=russian -V mainfont="Ubuntu"

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
