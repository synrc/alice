val assert=General.assert;
(*
 * Author:
 *   Andreas Rossberg <rossberg@ps.uni-sb.de>
 *
 * Copyright:
 *   Andreas Rossberg, 2001
 *
 * Last change:
 *   $Date: 2003-05-07 12:20:44 $ by $Author: rossberg $
 *   $Revision: 1.5 $
 *)

(*
 * Standard ML basic objects (shared between syntax and semantics)
 *
 * Definition, sections 2.2, 2.4, 3.2, 4.1, 5.1, 6.2, and 7.2
 *
 * Modifications:
 *   Longids are not included since they have been moved to the context-free
 *   grammar.
 *)




local
    structure Stamp = MkStamp()
in
    structure VId   = MkId(Stamp)
    structure TyCon = MkId(Stamp)
    structure TyVar = MkId(Stamp)
    structure StrId = MkId(Stamp)
    structure SigId = MkId(Stamp)
end
