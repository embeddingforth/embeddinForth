(* E37 G2 - noForth C&V 200202: Bit-bang I2C routines for MSP430G2 code variant
   This implementation is without clockbit stretching!!! Basic building blocks

  Connect the I2C-print from the Forth users group or any other module
  with I2C compatible chip{s} and connect the power lines. P1.7 to SDA and
  P1.6 to SCL, note that two 10k pullup resistors has te be mounted, that's it.

  User words:  I2C-ON  {I2C-WRITE  {I2C-READ   I2C}
               BUS@  BUS!  DEVICE!  {DEVICE-OK?}
  Additional:  {I2C-OUT  {I2C-IN  {POLL}  BUS!}  BUS@}  BUS-MOVE
 
  An example, first execute I2C-ON  After that the I2C is setup as
  a master. Sent byte 'b' to an I2C device with address 'a'.
    : >SLAVE    ( b a -- )  1 {i2c-write  bus!  i2c} ;
    : >PCF8574  ( b -- )    20 >slave ;

  10 20 - P1IN   Input bits
  10 21 - P1OUT  Output bits
  10 22 - P1DIR  Direction bits
  10 23 - P1IFG  Interrupt flag bits
  10 24 - P1IES  Interrupt edge select bits
  10 25 - P1IE   Interrupt enable bits
  10 26 - P1SEL  Function select bits
  10 27 - P1REN  Resistor enable bits
  10 41 - P1SEL2 Function select-2 bits
 *)

hex  v: inside also definitions
value DEV  value SUM  value NACK?
routine WAIT     ( -- adr ) \ Minimal period is 5 us, is about 100 kHz clock
\   0F # moon mov   \ 15 is about 5 us at 16MHz
    #4 moon mov     \ 4 is about 5 us at 8 MHz
    begin, #1 moon sub =? until,
    rp )+ pc mov              ( ret )
end-code

code I2START    ( -- )  \ Give I2C start condition
    40 # 21 & .b bis  40 # 22 & .b bic  \ P1OUT, P1DIR  set-scl
    wait # call
    80 # 22 & .b bis  80 # 21 & .b bic  \ P1DIR, P1OUT  clr-sda
    wait # call
    next
end-code

v: extra definitions
code BUS!       ( b -- )    \ Send the byte b out on the I2C bus
    tos w mov
    sp )+ tos mov
    #8 day mov
    begin,
        40 # 21 & .b bic  40 # 22 & .b bis  \ P1OUT, P1DIR  clr-scl
        w w .b add  cs? if,
          80 # 21 & .b bis  80 # 22 & .b bic \ P1OUT, P1DIR  set-sda
        else,
          80 # 21 & .b bic  80 # 22 & .b bis \ P1DIR, P1OUT  clr-sda
        then,
        wait # call
        40 # 21 & .b bis  40 # 22 & .b bic  \ P1OUT, P1DIR  set-scl
        wait # call
        #1 day sub
    =? until,       \ ready?
    40 # 21 & .b bic  40 # 22 & .b bis  \ P1OUT, P1DIR  clr-scl
    80 # 21 & .b bis  80 # 22 & .b bic  \ P1OUT, P1DIR  set-sda
    wait # call
    40 # 21 & .b bis  40 # 22 & .b bic  \ P1OUT, P1DIR  set-scl
    wait # call
    80 #  20 & .b bit                   \ P1IN  test ack
    sun sun subc                        \ Make flag
    #-1 sun bix                         \ Invert flag
    sun  adr NACK? & mov                \ Save ACK/NACK flag
    next
end-code

v: inside definitions
: {I2C-ADDR     ( +n -- )       drop  i2start  dev bus! ; \ Start I2C write with address from DEV


\ Higher level I2C access, hides internal details!
v: extra definitions
: I2C-ON        ( -- )
    C0 27 *bic  C0 22 *bic  C0 21 *bis  \ P1REN, P1DIR, P1OUT
    C0 26 *bic  C0 42 *bic ;            \ P1SEL, P1SEL2

\ Receive de byte b from the I2C bus
code BUS@       ( -- b )
    tos sp -) mov
    #0 tos mov
    #8 day mov
    begin,
        40 # 21 & .b bic  40 # 22 & .b bis  \ P1OUT, P1DIR  clr-scl
        80 # 21 & .b bis  80 # 22 & .b bic  \ P1OUT, P1DIR  set-sda)
        wait # call
        40 # 21 & .b bis  40 # 22 & .b bic  \ P1OUT, P1DIR  set-scl
        wait # call
        80 # 20 & .b bit                    \ P1IN  sda-in
        tos tos addc                        \ Add bit to 'b'
        #1 day sub
    =? until,       \ ready?
    #1 adr sum & sub
    40 # 21 & .b bic  40 # 22 & .b bis  \ P1OUT, P1DIR  clr-scl
    #0 adr sum & cmp                    \ ACK?
    0<>? if,    80 # 21 & .b bic        \ P1DIR, P1OUT  clr-sda
    else,       80 # 21 & .b bis        \ P1DIR, P1OUT  set-sda
    then,       80 # 22 & .b bis
    wait # call
    40 # 21 & .b bis  40 # 22 & .b bic  \ P1OUT, P1DIR  set-scl
    wait # call
    next
end-code

code I2C}       ( -- )  \ Give I2C stop condition
    40 # 21 & .b bic  40 # 22 & .b bis  \ P1OUT, P1DIR  clr-scl
    80 # 21 & .b bic  80 # 22 & .b bis  \ P1DIR, P1OUT  clr-sda
    wait # call
    40 # 21 & .b bis  40 # 22 & .b bic  \ P1OUT, P1DIR  set-scl
    wait # call
    80 # 21 & .b bis  80 # 22 & .b bic  \ P1OUT, P1DIR  set-sda
    next
end-code

code DEVICE!    ( a -- )
    tos tos add  FE # tos bia  tos adr dev & mov  sp )+ tos mov  next
end-code
: {DEVICE-OK?}  ( -- fl )   0 {i2c-addr  i2c}  nack? 0= ; \ 'f' is true when an ACK is received
: {I2C-WRITE    ( +n -- )   {i2c-addr  nack? ?abort ;   \ Start I2C write
: {I2C-READ     ( +n -- )   to sum  i2start  dev 1+ bus!  nack? ?abort ; \ Start read to device


\ Waiting for an EEPROM write to succeed is named acknowledge polling.
: {POLL}    ( -- )          begin  {device-ok?} until ; \ Wait until ACK received
: {I2C-OUT  ( dev +n -- )   swap  device!  {i2c-write ;
: {I2C-IN   ( dev +n -- )   swap  device!  {i2c-read ;
: BUS!}     ( b -- )        bus!  i2c} ;
: BUS@}     ( -- b )        bus@  i2c} ;
: BUS-MOVE  ( a u -- )      bounds ?do i c@ bus! loop ; \ Send string of bytes from 'a' with length 'u

v: fresh
shield BB-I2C\  freeze

\ End
