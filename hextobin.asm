; You have permission to use, modify, copy, and distribute
; this software so long as this copyright notice is retained.
; This software may not be used in commercial applications
; without express written permission from the author.


           ; Include kernal API entry points

           include bios.inc
           include kernel.inc


           ; Executable program header

           org     2000h - 6
           dw      start
           dw      end-start
           dw      start

start:     org     2000h
           br      entry

           ; Build information

           db      6+80h              ; month
           db      22                 ; day
           dw      2021               ; year
           dw      1                  ; build
           db      'Written by David S. Madole',0

           ; Main code starts here, check provided argument

entry:     glo     r6
           stxd
           ghi     r6
           stxd

skipspc1:  lda     ra                 ; skip any whitespace
           lbz     argsfail
           smi     '!'
           lbnf    skipspc1

           dec     ra

           ghi     ra
           phi     rf
           glo     ra                 ; remember start of name
           plo     rf

           inc     ra

skipchr1:  lda     ra                 ; end at null or space
           lbz     argsfail
           smi     '!'
           lbdf    skipchr1

           dec     ra

           ldi     0
           str     ra

           inc     ra

openfd1:   ldi     high fd1           ; get file descriptor
           phi     rd
           ldi     low fd1
           plo     rd

           ldi     0                  ; no options
           plo     r7

           sep     scall              ; open file
           dw      o_open

           lbdf    opn1fail

skipspc2:  lda     ra                 ; skip any whitespace
           lbz     argsfail
           smi     '!'
           lbnf    skipspc1

           dec     ra

           ghi     ra
           phi     rf
           glo     ra                 ; remember start of name
           plo     rf

           inc     ra

skipchr2:  lda     ra                 ; end at null or space
           lbz     openfd2
           smi     '!'
           lbdf    skipchr2

           lbr     argsfail

openfd2:   ldi     high fd2           ; get file descriptor
           phi     rd
           ldi     low fd2
           plo     rd

           ldi     1 + 2              ; create + truncate
           plo     r7

           sep     scall              ; open file
           dw      o_open

           lbdf    opn2fail

           ; General register usage in the main loop:
           ;
           ; R6   - Record counter
           ;
           ; R7.0 - State counter
           ; R7.1 - Input byte
           ; R8.0 - Data length
           ; R8.1 - Checksum
           ;
           ; R9   - Record buffer
           ;
           ; RA   - Input count
           ; RB   - Input buffer
           ;
           ; RC   - File i/o size
           ; RD   - File descriptor
           ; RE   - Reserved
           ; RF   - File i/o buffer

           ldi     0                  ; zero the state counter to read
           plo     r7                 ;  a new record

           plo     r6
           phi     r6

           ldi     1                  ; initialize the read byte value with
           phi     r7                 ;  bit 0 set to count 8 bits

           ; Loops back to here to get another chunk from the file

readmore:  ldi     high fd1           ; get file descriptor
           phi     rd
           ldi     low fd1
           plo     rd

           ldi     high 512           ; length to read at a time
           phi     rc
           ldi     low 512
           plo     rc

           ldi     high buffer        ; pointer to data buffer
           phi     rf
           ldi     low buffer
           plo     rf

           sep     scall              ; read from file
           dw      o_read

           ldi     high fd2           ; get file descriptor
           phi     rd
           ldi     low fd2
           plo     rd

           ldi     high buffer        ; pointer to data buffer
           phi     rb
           ldi     low buffer
           plo     rb

           dec     rc
           glo     rc
           plo     ra

           ghi     rc                 ; adjust so that we only need to
           adi     1                  ; test the msb in the loop later
           phi     ra

           lbz     return             ; if read count is 0, end of file

           lbr     readchar


           ; Loops back to this point for each input character

nextdata:  dec     r8

nexthead:  dec     ra                 ; check if there is another character
           ghi     ra                 ;  in the buffer, refill if not
           lbz     readmore

           inc     rb                 ; advance to next character

readchar:  glo     r7                 ; if state counter is not zero,
           lbnz    gethex             ;  get a hex byte

           ; Read a colon at the start of a record

getcolon:  ldn     rb                 ; get next character from buffer

           smi     '!'                ; if whitespace, then skip it
           lbnf    nexthead

           smi     ':'-'!'            ; if not a colon, then invalid
           lbnz    charfail

           inc     r6

           ldi     high record
           phi     r9
           ldi     low record
           plo     r9

           ldi     1
           phi     r7

           ldi     0                  ; set the top of stack to zero
           phi     r8                 ;  for checksum calculation

           inc     r7                 ; increase the state counter to 1
           lbr     nexthead           ;  and get next character

           ; Read a hex byte from the input file

gethex:    ldn     rb

           shl                        ; if bit 7 is set, not a valid ascii
           lbdf    charfail           ;  character, go and fail

           shl                        ; if bit 6 is set, then this could be
           lbdf    chkalpha           ;  an upper or lower case a-f

           shl                        ; if bit 5 is not set, then this is a
           lbnf    nexthead           ;  control character, skip it

           ; We have a byte like 001XXXXX so check if it's 0-9

           ldn     rb                 ; get original byte again
           
           smi     58                 ; if it is above a '9' digit, then
           lbdf    charfail           ;  it's invalid, go fail

           adi     10                 ; add to 10 to get place value,
           lbnf    charfail           ;  if negative, then it's invalid

           lbr     gotdigit           ; go store digit value

           ; We have a byte like 01XXXXXX so check if it's A-F/a-f

chkalpha:  ldn     rb                 ; get original byte again

           ani     31                 ; change A-Z or a-z to 1-26 range,
           lbz     charfail           ;  if it is zero then it's invalid

           smi     7                  ; if it is above 6 which is 'F', then
           lbdf    charfail           ;  it's invalid, go fail

           adi     16                 ; add 16 to bring 'A'-'F' to 10-16

           ; Add the new digit into the current byte value

gotdigit:  str     r2

           ghi     r7                 ; get current value so far and shift
           shl                        ;  four bits to left
           shl
           shl
           shl

           or                         ; add in the new digit and store
           phi     r7                 ;  back to register

           lbnf    nexthead           ; if 0 shifted out, get another digit

           str     r9                 ; save into the buffer
           inc     r9

           str     r2

           ghi     r8
           add                        ; update checksum which is on the
           phi     r8                 ;  top of the stack

           ldi     1                  ; initialize the read byte value with
           phi     r7                 ;  bit 0 set to count 8 bits

           glo     r7                 ; get current state counter and
           sdi     4                  ;  compare to 5 overhead bytes
           lbnf    getdata            ;  if more than 5, get data bytes
           lbnz    gethead            ;  if exactly 5, header is read

           ldi     high length
           phi     rf
           ldi     low length
           plo     rf

           ldn     rf                 ; get length from header and
           plo     r8                 ;  store into counter

gethead:   inc     r7                 ; increment state counter by 1
           lbr     nexthead           ;  and get next byte

getdata:   glo     r8                 ; if still bytes left in record, then
           lbnz    nextdata           ;  continue reading

           ghi     r8
           lbnz    csumfail           ;  be zero if record is valid

           ; If any data was in this record, write it to the output file
           ; at the correct offset specified by the address in the record.

           ldi     high record        ; get pointer to the record
           phi     rf
           ldi     low record
           plo     rf

           lda     rf                 ; get record data length,
           lbz     skipdata           ;  if zero, then don't write

           lda     rf                 ; get record address and put into
           phi     r7                 ;  seek low 16 bits input argument
           ldn     rf
           plo     r7

           ldi     0                  ; clear seek high 16 bits input
           plo     r8
           phi     r8

           plo     rc                 ; relative to beginning of file

           sep     scall              ; seek on output file
           dw      o_seek

           dec     rf                 ; point back to record length
           dec     rf
           
           lda     rf                 ; get record length
           plo     rc                 ;  put into low byte of write size

           ldi     0                  ; clear high byte of write size
           phi     rc

           inc     rf                 ; advance pointer to data field
           inc     rf
           inc     rf

           sep     scall              ; write data to output file
           dw      o_write

skipdata:  ldi     0                  ; zero the state counter to read
           plo     r7                 ;  a new record

           lbr     nexthead           ; go start next record


           ; Return to caller when done but close both files first

return:    ldi     high fd1           ; pointer to fd1
           phi     rd
           ldi     low fd1
           plo     rd
           
           sep     scall              ; close fd1
           dw      o_close

           ldi     high fd2           ; pointer to fd2
           phi     rd
           ldi     low fd2
           plo     rd
           
           sep     scall              ; close fd2
           dw      o_close

           inc     r2                 ; restore link register from start
           lda     r2
           phi     r6
           ldn     r2
           plo     r6

           sep     sret               ; exit back to operating system


           ; If the command arguments are incorrect

argsfail:  ldi     argsmesg.1   ; if supplied argument is not valid
           phi     rf
           ldi     argsmesg.0
           plo     rf

           lbr     printmsg

           ; if the input file can't be opened

opn1fail:  ldi     opn1mesg.1   ; if unable to open input file
           phi     rf
           ldi     opn1mesg.0
           plo     rf

           lbr     printmsg

           ; If the output file can't be opened

opn2fail:  ldi     opn2mesg.1   ; if unable to open input file
           phi     rf
           ldi     opn2mesg.0
           plo     rf

           lbr     printmsg

           ; If a checksum is incorrect in a record

csumfail:  ldi     csummesg.1   ; if supplied argument is not valid
           phi     rd
           ldi     csummesg.0
           plo     rd

           lbr     recordno

           ; If a bad input character is found in a record

charfail:  ldi     high charmesg
           phi     rd
           ldi     low charmesg
           plo     rd

recordno:  ldi     high buffer
           phi     rf
           ldi     low buffer
           plo     rf

           dec     rf

strcpy:    inc     rf
           lda     rd
           str     rf
           lbnz    strcpy

           ghi     r6
           phi     rd
           glo     r6
           plo     rd

           sep     scall
           dw      f_uintout

           ldi     0
           str     rf

           ldi     high buffer
           phi     rf
           ldi     low buffer
           plo     rf

printmsg:  sep     scall
           dw      o_msg

           ldi     high crlf
           phi     rf
           ldi     low crlf
           plo     rf

           sep     scall
           dw      o_msg

           lbr     return

argsmesg:  db      'Usage: hextobin input-file output-file',0
opn1mesg:  db      'Open input file failed',0
opn2mesg:  db      'Open output file failed',0
charmesg:  db      'Invalid character at record ',0
csummesg:  db      'Checksum failed at record ',0
crlf:      db      13,10,0

           ; Include file descriptor in program image so it is initialized.

fd1:       db      0,0,0,0
           dw      dta1
           db      0,0
fd1flags:  db      0
           db      0,0,0,0
           dw      0,0
           db      0,0,0,0

fd2:       db      0,0,0,0
           dw      dta2
           db      0,0
fd2flags:  db      0
           db      0,0,0,0
           dw      0,0
           db      0,0,0,0

end:       ; These buffers are not included in the executable image but will
           ; will be in memory immediately following the loaded image.

dta1:      ds      512
dta2:      ds      512
buffer:    ds      512

record:    ; Structure for reading input record into

length:    ds      1
address:   ds      2
type:      ds      1
data:      ds      255
checksum:  ds      1

mem:       ; this is how much memory is needed at runtime

