import bitops
import token
import strutils

# maybe consider using array[3, uint8]] for everything
# This is a forum post that tries to solve the same problem I have with all that converting between uint8 and uint32
# https://forum.nim-lang.org/t/2626
type
  VMState* = ref object
    buf*: seq[array[3, uint8]]
    ir*: array[3, uint8]
    ra*: uint
    iar*: uint
    a*: uint
    one*: uint
    minus_one: uint
    sp*: uint
    fp*: uint
    sar*: uint
    sdr*: uint
    x*: uint
    y*: uint
    mem*: array[1024, array[3, uint8]] # technically 2^20 mb of RAM should be supported
    running*: bool

proc makeVM*(buf: seq[array[3, uint8]], mem: array[1024, array[3, uint8]]): VMState =
  VMState(buf: buf, ir: [(uint8) 0, (uint8) 0, (uint8) 0], ra: 0, iar: 0, a: 0, one: 1, minus_one: 0x00ffffff, sp: 1, fp: 0, sar: 0, sdr: 0, x: 0, y: 0, mem: mem, running: true)

# this could be a macro but somehow macros seem to be broken or something (at least when using static array values)
proc construct*(instr: array[3, uint8]): uint = # redo using cast[] stuff maybe
  return (bitand(instr[0], 0x0f) shl 16) + (instr[1] shl 8) + (instr[2])

proc destruct*(instr: uint): array[3, uint8] = # redo using cast[] stuff maybe
  [(uint8) (bitand(instr, 0x0f0000) shr 16), (uint8) (bitand(instr, 0xff00) shr 8), (uint8) bitand(instr, 0xff)]

proc execute*(state: VMState): VMState =
  if state.iar > cast[uint](len(state.buf)):
    state.running = false
    return state
  
  state.ir = state.buf[state.iar] # 24-bit
  var instruction = state.ir
  # echo instruction
  case cast[uint8](bitand(instruction[0], 0xf0)):
    of ord(opcodes.LDC):
      state.a = construct(instruction)
      state.iar += 1
    of ord(opcodes.LDV): # technically 2^20 mb of RAM should be supported
      state.a = construct(state.mem[construct(instruction)])
      state.iar += 1
    of ord(opcodes.STV):
      state.mem[construct(instruction)] = destruct(state.a)
      state.iar += 1
    of ord(opcodes.ADD):
      state.a = bitand(state.a + construct(state.mem[construct(instruction)]), 0x00ffffff)
      state.iar += 1
    of ord(opcodes.AND):
      state.a = bitand(state.a, construct(state.mem[construct(instruction)]))
      state.iar += 1
    of ord(opcodes.OR):
      state.a = bitor(state.a, construct(state.mem[construct(instruction)]))
      state.iar += 1
    of ord(opcodes.XOR):
      state.a = bitxor(state.a, construct(state.mem[construct(instruction)]))
      state.iar += 1
    of ord(opcodes.EQL):
      if state.a == construct(state.mem[construct(instruction)]):
        state.a = state.minus_one
      else:
        state.a = 0
      state.iar += 1
    of ord(opcodes.JMP):
      state.iar = construct(instruction)
    of ord(opcodes.JMN):
      if bitand(state.a, 0x00800000) == 0x00800000:
        state.iar = construct(instruction)
      else:
        state.iar += 1
    of ord(opcodes.LDIV):
      state.a = construct(state.mem[construct(state.mem[construct(instruction)])])
      state.iar += 1
    of ord(opcodes.STIV):
      state.mem[construct(state.mem[construct(instruction)])] = destruct(state.a)
      state.iar += 1
    of ord(opcodes.CALL):
      state.ra = state.iar + 1
      state.iar = construct(instruction)
    of ord(opcodes.ADC):
      state.a += construct(instruction)
      state.iar += 1

    # this is a placeholder for extended-opcodes-2
    of ord(opcodes.LDVR):
      case instruction[0]
        of ord(opcodes.LDVR_FP):
          let offset: int16 = cast[int16]((instruction[1] shl 8) + instruction[2])
          state.a = construct(state.mem[cast[int](state.fp) + offset])
          state.iar += 1
        of ord(opcodes.STVR_FP):
          let offset: int16 = cast[int16]((instruction[1] shl 8) + instruction[2])
          state.mem[cast[int](state.fp) + offset] = destruct(state.a)
          state.iar += 1
        of ord(opcodes.LDVR_RA):
          let offset: int16 = cast[int16]((instruction[1] shl 8) + instruction[2])
          state.a = construct(state.mem[cast[int](state.ra) + offset])
          state.iar += 1
        of ord(opcodes.STVR_RA):
          let offset: int16 = cast[int16]((instruction[1] shl 8) + instruction[2])
          state.mem[cast[int](state.ra) + offset] = destruct(state.a)
          state.iar += 1
        of ord(opcodes.LDVR_SP):
          let offset: int16 = cast[int16]((instruction[1] shl 8) + instruction[2])
          state.a = construct(state.mem[cast[int](state.sp) + offset])
          state.iar += 1
        of ord(opcodes.STVR_SP):
          let offset: int16 = cast[int16]((instruction[1] shl 8) + instruction[2])
          state.mem[cast[int](state.sp) + offset] = destruct(state.a)
          state.iar += 1
        else:
          echo "error extended-opcodes-2"

    # this is a placeholder for extended-opcodes-1
    of ord(opcodes.HALT):

      case instruction[0]:
        of ord(opcodes.HALT):
          state.running = false
          return state
        of ord(opcodes.NOT):
          state.a = bitand(bitnot(state.a), state.one)
          state.iar += 1
        of ord(opcodes.RAR):
          state.a = bitor(bitand(state.a, 1) shl 24, bitand(state.a, 0x00ffffff) shr 1)
          state.iar += 1
        of ord(opcodes.RET):
          state.iar = state.ra
        of ord(opcodes.LDSP):
          state.a = state.sp
          state.iar += 1
        of ord(opcodes.STSP):
          state.sp = state.a
          state.iar += 1
        of ord(opcodes.LDFP):
          state.a = state.fp
          state.iar += 1
        of ord(opcodes.STFP):
          state.fp = state.a
          state.iar += 1
        of ord(opcodes.LDRA):
          state.a = state.ra
          state.iar += 1
        of ord(opcodes.STRA):
          state.ra = state.a
          state.iar += 1
        else:
          echo "error extended-opcodes-1"
    else:
      echo "error"
  state.running = true
  return state

proc get_reg_by_string*(vmstate: VMState, register: string): uint =
  if register.toUpper() notin @["A", "IR", "IAR", "RA", "SP", "FP", "SAR", "SDR", "X", "Y"]:
    raise new_exception(ValueError, "not a valid register")

  result = case register:
    of "A":
      vmstate.a
    of "IR":
      construct(vmstate.ir)
    of "IAR":
      vmstate.iar
    of "RA":
      vmstate.ra
    of "SP":
      vmstate.sp
    of "FP":
      vmstate.fp
    of "SAR":
      vmstate.sar
    of "SDR":
      vmstate.sdr
    of "X":
      vmstate.x
    of "Y":
      vmstate.y
    else:
      raise new_exception(ValueError, "not a valid register")

proc set_reg_by_string*(vmstate: VMState, register: string, value: uint) =
  if register.toUpper() notin @["A", "IR", "IAR", "RA", "SP", "FP", "SAR", "SDR", "X", "Y"]:
    raise new_exception(ValueError, "not a valid register")
  
  case register:
    of "A":
      vmstate.a = value
    of "IR":
      vmstate.ir = destruct(value)
    of "IAR":
      vmstate.iar = value
    of "RA":
      vmstate.ra = value
    of "SP":
      vmstate.sp = value
    of "FP":
      vmstate.fp = value
    of "SAR":
      vmstate.sar = value
    of "SDR":
      vmstate.sdr = value
    of "X":
      vmstate.x = value
    of "Y":
      vmstate.y = value
    else:
      raise new_exception(ValueError, "not a valid register")