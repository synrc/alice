val assert=General.assert;
(*
 * Author:
 *   Andreas Rossberg <rossberg@ps.uni-sb.de>
 *
 * Copyright:
 *   Andreas Rossberg, 2001-2003
 *
 * Last change:
 *   $Date: 2003-07-18 13:54:41 $ by $Author: rossberg $
 *   $Revision: 1.10 $
 *)

signature STAMP =
sig
    eqtype stamp
    type t = stamp

    (*val reset :	unit -> unit*)
    val stamp :		unit -> stamp
    val toString :	stamp -> string

    val equal :		stamp * stamp -> bool
    val compare :	stamp * stamp -> order
    val hash :		stamp -> int
end
