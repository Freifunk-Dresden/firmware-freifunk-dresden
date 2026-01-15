all:	doc


doc:	Makefile
#	latex2html -split 0 -noinfo bmx.tex
#	latex2html -split 0 -noinfo bmx.tex
	pdflatex bmx.tex
	pdflatex bmx.tex
	rm -rv *.toc *.log *.aux
	
	
clean:
	rm -rfv *.toc *.pdf *.log *.aux 
#$$(find  -type d | grep "./")