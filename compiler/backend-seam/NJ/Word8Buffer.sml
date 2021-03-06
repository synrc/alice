val assert=General.assert;
(*
 * Author:
 *   Guido Tack <tack@ps.uni-sb.de>
 *
 * Copyright:
 *   Guido Tack, 2003
 *
 * Last change:
 *   $Date: 2003-06-11 11:37:02 $ by $Author: tack $
 *   $Revision: 1.1 $
 *)






structure Word8Buffer :> WORD8_BUFFER =
    struct
	type t = Word8Array.array ref * int ref * int ref

	fun buffer () = (ref (Word8Array.tabulate (10,
						   fn x => Word8.fromInt x)),
			 ref 10,
			 ref 0)

	fun enlarge (array, size, count) =
	    let
		val newArray = Word8Array.tabulate
		    ((!size*2),
		     (fn i =>
		      if i>= (!size) then Word8.fromInt 0
		      else Word8Array.sub (!array, i)))
	    in
		array := newArray;
		size := !size*2
	    end
	    
	fun output1 (b, w) =
	    let
		val (array, size, count) = b
	    in
		if !count= !size then
		    (enlarge b;
		     output1 (b, w))
		else
		    (Word8Array.update (!array, !count, w);
		    count := !count + 1)
	    end

	fun getVector (array, size, count) =
	    Word8Vector.tabulate ((!count),
	    (fn i => Word8Array.sub (!array, i)))

	fun bufferSize (array, size, count) = !count
			 
    end
