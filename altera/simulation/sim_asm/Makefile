.PHONY:		all clean

ASMTARGETS=	acceltest.rom 
TARGETS=	$(ASMTARGETS) 

INCS=		hw.inc common.inc os.inc
LIBS=		
SCRIPTS=../../scripts
BUILD=./build


AS=ca65
LD=ld65
DEPS=$(INCS)
AR=ar65

.PRECIOUS:	$(BUILD)/%.o

X:=$(shell mkdir -p build)

all:		$(addprefix $(BUILD)/, $(TARGETS))

$(BUILD)/%rom:	%.cfg

$(BUILD)/%.rom:	$(BUILD)/%.o $(LIBS)
		$(LD) -vm -Ln $(basename $@).sy2 -m $(basename $@).map -o $@ -C $(notdir $(basename $@)).cfg $< $(LIBS)
		#$(SCRIPTS)/perl/getsymbols.pl <$(basename $@).sy2 >$(basename $@).sym.noi
		da65 -S 0xC000 --comments 4 $(basename $@).rom >$(basename $@).da.s


$(BUILD)/%.o:	%.asm $(DEPS) $(INCS)
		$(AS) -g -l $(basename $@).lst -o $@ $<


clean:		
		-rm -f $(BUILD)/*



