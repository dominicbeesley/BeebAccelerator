.PHONY:		all clean

ASMTARGETS=	LBAS15.bin
TARGETS=	$(ASMTARGETS) 

INCS=		
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

$(BUILD)/%bin:	%.cfg

$(BUILD)/%.bin:	$(BUILD)/%.o $(LIBS)
		$(LD) -vm -Ln $(basename $@).sy2 -m $(basename $@).map -o $@ -C $(notdir $(basename $@)).cfg $< $(LIBS)
		#$(SCRIPTS)/perl/getsymbols.pl <$(basename $@).sy2 >$(basename $@).sym.noi
		da65 -S 0xC000 --comments 4 $(basename $@).bin >$(basename $@).da.s
		echo "$$.LBAS15 FFFF2000 FFFF2000" >$(basename $@).bin.inf

$(BUILD)/%.o:	%.asm $(DEPS) $(INCS)
		$(AS) -g -l $(basename $@).lst -o $@ $<

deploy:	all
		cp $(BUILD)/LBAS15.bin ~/hostfs/0.TEST
		cp $(BUILD)/LBAS15.bin.inf ~/hostfs/0.TEST


clean:		
		-rm -f $(BUILD)/*



