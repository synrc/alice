val assert=General.assert;
(*
 * Author:
 *   Leif Kornstaedt <kornstae@ps.uni-sb.de>
 *
 * Contributor:
 *   Guido Tack <tack@ps.uni-sb.de>
 *
 * Copyright:
 *   Leif Kornstaedt, 2000-2002
 *   Guido Tack, 2003
 *
 * Last change:
 *   $Date: 2007-04-12 14:02:30 $ by $Author: tack $
 *   $Revision: 1.23 $
 *)










structure PrimPickle :> PRIM_PICKLE =
    struct
	structure AtomMap = MkHashImpMap(Atom)

	type outstream =
	     {stream: BinIO.outstream,
	      buffer: Word8Buffer.t,
	      nextRegister: int ref,
	      stringMap: int StringMap.t,
	      atomMap: int AtomMap.t,
	      maxStack: int ref,
	      curStack: int ref}

	type register = int

	fun nextRegister ({nextRegister = r as ref reg, ...} : outstream) =
	    (r := reg + 1; reg)

	type label = int
	type size = int

        val majorVersion = 5
        val minorVersion = 0
        val magicS = Word8.fromInt (Char.ord #"s")
        val magicE = Word8.fromInt (Char.ord #"e")
        val magicA = Word8.fromInt (Char.ord #"a")
        val magicM = Word8.fromInt (Char.ord #"m")
	
	val tINIT        = Word8.fromInt 0
	val tSTORE       = Word8.fromInt 1
	val tLOAD        = Word8.fromInt 2
	val tPOSINT      = Word8.fromInt 3
	val tNEGINT      = Word8.fromInt 4
	val tCHUNK       = Word8.fromInt 5
	val tMCHUNK      = Word8.fromInt 6
	val tUNIQUE      = Word8.fromInt 7
	val tBLOCK       = Word8.fromInt 8
	val tMBLOCK      = Word8.fromInt 9
	val tTUPLE       = Word8.fromInt 10
	val tCLOSURE     = Word8.fromInt 11
	val tTRANSFORM   = Word8.fromInt 12
	val taBLOCK      = Word8.fromInt 13
	val taMBLOCK     = Word8.fromInt 14
	val taTUPLE      = Word8.fromInt 15
	val taCLOSURE    = Word8.fromInt 16
	val taTRANSFORM  = Word8.fromInt 17
	val tFULFIL      = Word8.fromInt 18
	val tENDOFSTREAM = Word8.fromInt 19

	fun streamOutputByte ({stream, ...}: outstream, w) =
	    BinIO.output1 (stream, w)

	fun streamOutputUInt (q, i) =
	    if i >= 0x80 then
		(streamOutputByte (q, Word8.fromInt (i mod 0x80 + 0x80));
		 streamOutputUInt (q, i div 0x80))
	    else if i >= 0 then streamOutputByte (q, Word8.fromInt i)
	    else raise Crash.Crash "PrimPickle.streamOutputUInt"

	fun outputByte ({buffer, ...}: outstream, w) =
	    Word8Buffer.output1 (buffer, w)

        val ox8o = FixedInt.fromInt 0x80
        val fixedIntToWord8 = Word8.fromInt o FixedInt.toInt
	fun outputFixedUInt (q, i) =
	    if i >= ox8o then
		(outputByte (q, fixedIntToWord8 (i mod ox8o + ox8o));
		 outputFixedUInt (q, i div ox8o))
	    else if i >= 0 then outputByte (q, fixedIntToWord8 i)
	    else raise Crash.Crash "PrimPickle.outputUInt"
        fun outputUInt (q, i) = outputFixedUInt (q, FixedInt.fromInt i)

	fun openOut name: outstream =
	    {stream = BinIO.openOut name,
	     buffer = Word8Buffer.buffer (),
	     nextRegister = ref 1,
	     stringMap = StringMap.map (),
	     atomMap = AtomMap.map (),
	     maxStack = ref 0,
	     curStack = ref 0}

	fun push ({maxStack, curStack, ...} : outstream) =
	    let
		val _ = curStack := (!curStack) + 1
	    in
		if !curStack > (!maxStack) then
		    maxStack := (!curStack)
		else
		    ()
	    end

	fun pop ({curStack, ...} : outstream, i) =
	    curStack := !curStack - i

	fun outputFixedInt (q, i) =
	    (if i >= FixedInt.fromInt 0 then
                 (outputByte (q, tPOSINT); outputFixedUInt (q, i))
	     else
                 (outputByte (q, tNEGINT);
                  outputFixedUInt (q, ~(i + FixedInt.fromInt 1)));
	     push q)

	fun outputInt (q, i) =
	    (if i >= 0 then
                 (outputByte (q, tPOSINT); outputUInt (q, i))
	     else
                 (outputByte (q, tNEGINT);
                  outputUInt (q, ~(i + 1)));
	     push q)

	fun outputChunk (q, bytes) =
	    (outputByte (q, tCHUNK);
	     outputUInt (q, Word8Vector.length bytes);
	     Word8Vector.app (fn b => outputByte (q, b)) bytes;
	     push q)

	fun outputMChunk (q, bytes) =
	    (outputByte (q, tMCHUNK);
	     outputUInt (q, Word8Vector.length bytes);
	     Word8Vector.app (fn b => outputByte (q, b)) bytes;
	     push q)

	fun outputUnique q =
	    (outputByte (q, tUNIQUE))
	    
	fun outputBlock (q, label, size) =
	    (outputByte (q, tBLOCK);
	     outputUInt (q, label);
	     outputUInt (q, size);
	     pop (q, size-1))

	fun outputMBlock (q, label, size) =
	    (outputByte (q, tMBLOCK);
	     outputUInt (q, label);
	     outputUInt (q, size);
	     pop (q, size-1))

	fun outputTuple (q, size) =
	    (outputByte (q, tTUPLE);
	     outputUInt (q, size);
	     pop (q, size-1))

	fun outputClosure (q, size) =
	    (outputByte (q, tCLOSURE);
	     outputUInt (q, size);
	     pop (q, size-1))

	fun outputTransform q =
	    (outputByte (q, tTRANSFORM);
	     pop (q, 1))
	    
	fun outputLoad (q, i) =
	    (outputByte (q, tLOAD);
	     outputUInt (q,i);
	     push q)

	fun outputStore (q, i) =
	    (outputByte (q, tSTORE);
	     outputUInt (q,i))

	fun outputString (q as {stringMap, ...}: outstream, s) =
	    case StringMap.lookup (stringMap, s) of
		SOME id => (outputLoad (q, id))
	      | NONE =>
		    let
			val id = nextRegister q
		    in
			StringMap.insertDisjoint (stringMap, s, id);
			outputByte (q, tCHUNK);
			outputUInt (q, String.size s);
			CharVector.app
			(fn c => outputByte (q, Word8.fromInt (Char.ord c))) s;
			outputStore (q, id);
			push q
		    end

	fun outputAtom (q as {atomMap, ...}: outstream, s) =
	    case AtomMap.lookup (atomMap, s) of
		SOME id => (outputLoad (q, id))
	      | NONE =>
		    let
			val id = nextRegister q
		    in
			AtomMap.insertDisjoint (atomMap, s, id);
			outputString (q, Atom.toString s);
			outputUnique q;
			outputStore (q,id);
			push q
		    end

	fun closeOut (q as {stream, buffer, maxStack, ...}: outstream) =
	    let
		val charVector = Word8Buffer.getVector buffer
	    in
                (streamOutputByte (q, magicS);
                 streamOutputByte (q, magicE);
                 streamOutputByte (q, magicA);
                 streamOutputByte (q, magicM);
		 streamOutputUInt (q, majorVersion);
		 streamOutputUInt (q, minorVersion);
                 streamOutputByte (q, tINIT);
		 streamOutputUInt (q, !maxStack);
		 streamOutputUInt (q, nextRegister q);
		 BinIO.output (stream, charVector);
		 streamOutputByte (q, tSTORE);
		 streamOutputUInt (q, 0);
		 streamOutputByte (q, tENDOFSTREAM);
		 BinIO.closeOut stream)
	    end
    end
