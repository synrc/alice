val assert=General.assert;
(*
 * Authors:
 *   Andreas Rossberg <rossberg@ps.uni-sb.de>
 *
 * Copyright:
 *   Andreas Rossberg, 2003
 *
 * Last change:
 *   $Date: 2003-07-11 16:33:04 $ by $Author: rossberg $
 *   $Revision: 1.1 $
 *)

signature DEPENDENCY =
sig
    type dependency
    type t = dependency

    exception Format

    val empty :  dependency
    val load :   dependency * string -> dependency
    val lookup : dependency * string -> string list
end
