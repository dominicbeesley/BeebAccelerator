

MOSVAR_CURLANG 	= $28C

zp_mos_currom	= $F4

sheila_romsel	= $FE30

OSWRCH = $FFEE

		.zeropage
zp_ptr:		.res	2		; rom pointer
zp_printptr:	.res	2

		.code
main:		lda	zp_mos_currom
		pha


		jsr	printIm
		.byte	"Copy to 15",13,10,0

		lda	MOSVAR_CURLANG
		cmp	#15
		bne	main_slot_ok

		brk
		.byte	255, "Current language is already slot #15", 0

main_slot_ok:	
		; check rom #15 writeable

		jsr	printIm
		.byte	"Check writeable...",13,10,0

		sei
		lda	#15
		sta	zp_mos_currom
		sta	sheila_romsel
		lda	#0
		sta	$8000
		eor	$8000
		bne	nowrite
		lda	#$FF
		sta	$8000
		eor	$8000
		beq	okwrite

nowrite:	lda	MOSVAR_CURLANG
		sta	zp_mos_currom
		sta	sheila_romsel

		brk
		.byte	255, "ROM slot 15 doesn't appear to be writeable",0

okwrite:	
		jsr	printIm
		.byte	"Clear rom #15...",13,10,0

		; clear ROM #15 first page
		jsr	clearStart
		jsr	clearCheck
		beq	main_ok_clear

		jsr	printIm
		.byte	"Failed to clear at ",0
		jsr	printHexXY

		brk	
		.byte	255, "Clear failed",0
main_ok_clear:

		jsr 	printIm
		.byte	"Starting copy....",0

		; copy current language to rom
		jsr	doCopy
		beq	alldone
		
		jsr	printIm
		.byte	"Copy failed at",0
		jsr	printHexXY
		jsr	printIm
		.byte	"read back ",0
		ldy	#0
		lda	(zp_ptr),Y
		jsr	printHexA
		jsr	printIm
		.byte   "expected ",0
		ldx	MOSVAR_CURLANG
		stx	zp_mos_currom
		stx	sheila_romsel
		ldy	#0
		lda	(zp_ptr),Y
		jsr	printHexA
		jsr	printIm

		jsr	printIm
		.byte	13,10,0

		brk
		.byte	255, "Copy to slot 15 failed",0
	

alldone:
		cli
		jsr	printIm
		.byte	"OK - press CTRL-break",13,10,0

		; put back original rom
		pla
		sta	zp_mos_currom
		sta	sheila_romsel
		rts


doCopy:
		jsr	resetPtr
@lp:		ldx	MOSVAR_CURLANG
		stx	zp_mos_currom
		stx	sheila_romsel
		lda	(zp_ptr),Y
		ldx	#15
		stx	zp_mos_currom
		stx	sheila_romsel
		sta	(zp_ptr),Y
		eor	(zp_ptr),Y
		bne	@notok
		iny
		bne	@lp
		inc	zp_ptr+1
		ldx	zp_ptr+1
		cpx	#$C0
		bne	@lp
		rts
@notok:		jsr	addYPtr
		rts		

clearStart:	jsr	resetPtr
@lp:		sta	(zp_ptr),Y
		iny
		bne	@lp
		inc	zp_ptr+1
		ldx	zp_ptr+1
		cpx	#$C0
		bne	@lp
		rts

clearCheck:	jsr	resetPtr
@lp:		lda	(zp_ptr),Y
		bne	@sk_no
		iny
		bne	@lp
		inc	zp_ptr+1
		ldx	zp_ptr+1
		cpx	#$C0
		bne	@lp
		rts
@sk_no:		jsr	addYPtr		; should leave Z clear
		rts
		
addYPtr:	tya
		clc
		adc	zp_ptr
		sta	zp_ptr
		tax
		lda	#0
		adc	zp_ptr+1
		sta	zp_ptr+1
		tay
		rts


resetPtr:	lda	#$80
		sta	zp_ptr+1
		ldy	#0
		sty	zp_ptr
		tya
		rts

printIm:	pha
		txa
		pha
		tya
		pha

		tsx

		lda	$104,X
		sta	zp_printptr
		lda	$105,X
		sta	zp_printptr+1
		ldy	#1
@lp:		lda	(zp_printptr),Y
		beq	@sk
		jsr	OSWRCH
		iny
		bne	@lp
		inc	zp_printptr+1
@sk:		clc
		tya
		adc	zp_printptr
		sta	$104,X
		lda	#0
		adc	zp_printptr+1
		sta	$105,X
		pla
		tay
		pla
		tax
		pla
		rts

printHexA:	pha
		lsr	a
		lsr	a
		lsr	a
		lsr	a
		jsr	printHexNybA
		pla
		pha
		jsr	printHexNybA
		pla
		rts
printHexNybA:	and	#$0F
		cmp	#10
		bcc	@1
		adc	#'A'-'9'-2
@1:		adc	#'0'
		jsr	OSWRCH
		rts

printHexXY:	pha
		tya
		jsr	printHexA
		txa
		jsr	printHexA
		pla
		rts


