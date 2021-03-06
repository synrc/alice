val assert=General.assert;
(*
 * Author:
 *   Leif Kornstaedt <kornstae@ps.uni-sb.de>
 *
 * Copyright:
 *   Leif Kornstaedt, 1999-2000
 *
 * Last change:
 *   $Date: 2002-08-01 13:50:45 $ by $Author: rossberg $
 *   $Revision: 1.9 $
 *)









structure LabelSort: LABEL_SORT =
    struct
	datatype arity =
	    Tup of int
	  | Prod

	fun sort get =
	    let
		fun isTuple (xs, i, n) =
		    if i = n then SOME n
		    else if get (Vector.sub (xs, i)) = Label.fromInt (i + 1) then
			isTuple (xs, i + 1, n)
		    else NONE

		fun compare (x1, x2) = Label.compare (get x1, get x2)
		val sortList = List.sort compare
	    in
		fn xs =>
		    let
			val xs' = Vector.fromList (sortList xs)
		    in
			case isTuple (xs', 0, Vector.length xs') of
			    SOME i => (xs', Tup i)
			  | NONE => (xs', Prod)
		    end
	    end
    end
