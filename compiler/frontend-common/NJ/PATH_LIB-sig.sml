val assert=General.assert;
(*
 * Authors:
 *   Andreas Rossberg <rossberg@ps.uni-sb.de>
 *
 * Copyright:
 *   Andreas Rossberg, 2001-2004
 *
 * Last change:
 *   $Date: 2004-04-11 19:33:54 $ by $Author: rossberg $
 *   $Revision: 1.3 $
 *)



signature PATH_LIB =
sig
    val modlab_path :		Label.t
    val typlab_path :		Label.t

    val lab_invent :		Label.t
    val lab_pervasive :		Label.t
    val lab_fromLab :		Label.t
    val lab_fromString :	Label.t
end
