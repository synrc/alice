val assert=General.assert;
(*
 * Author:
 *   Andreas Rossberg <rossberg@ps.uni-sb.de>
 *
 * Copyright:
 *   Andreas Rossberg, 2001-2003
 *
 * Last change:
 *   $Date: 2003-07-18 14:27:32 $ by $Author: rossberg $
 *   $Revision: 1.15 $
 *)




functor MkStamp() :> STAMP =
struct
    type stamp   = int
    type t       = stamp

    val r        = ref 0
    val lock     = Lock.lock()

    val reset    = Lock.sync lock (fn() => r := 0)
    val stamp    = Lock.sync lock (fn() => (ignore TextIO.stdIn; r := !r+1; !r))

    val toString = Int.toString
    val compare  = Int.compare
    val equal    = op =

    fun hash n   = n
end
