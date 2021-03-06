val assert=General.assert;
(*
 * Author:
 *   Andreas Rossberg <rossberg@ps.uni-sb.de>
 *
 * Copyright:
 *   Andreas Rossberg, 2001-2005
 *
 * Last change:
 *   $Date: 2005-03-01 13:53:35 $ by $Author: rossberg $
 *   $Revision: 1.10 $
 *)

(* Error handling. *)






signature ERROR =
sig
    (* Import *)

    type region = Source.region
    type doc    = PrettyPrint.doc

    (* Export *)

    exception Error of region * doc

    val setCurrentUrl :	Url.t option -> unit
    val setOutstream :	TextIO.StreamIO.outstream -> unit
    val setOutWidth :	int -> unit

    val error :		region * doc -> 'a
    val warn :		bool * region * doc -> unit
    val error' :	region * string -> 'a
    val warn' :		bool * region * string -> unit
    val unfinished :	region * string * string -> 'a
 end
