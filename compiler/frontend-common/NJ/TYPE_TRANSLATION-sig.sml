val assert=General.assert;
(*
 * Author:
 *   Andreas Rossberg <rossberg@ps.uni-sb.de>
 *
 * Copyright:
 *   Andreas Rossberg, 2001-2004
 *
 * Last change:
 *   $Date: 2004-09-22 12:44:37 $ by $Author: rossberg $
 *   $Revision: 1.10 $
 *)







signature TYPE_TRANSLATION =
sig
    (* RTT types *)

    val name_dynamic	: Name.t

    val modlab_rtt	: Label.t

    val typ_unit	: Type.t

    val typ_fix		: TranslationEnv.t -> Type.t
    val typ_assoc	: TranslationEnv.t -> Type.t
    val typ_lab		: TranslationEnv.t -> Type.t
    val typ_path	: TranslationEnv.t -> Type.t
    val typ_typ		: TranslationEnv.t -> Type.t
    val typ_var		: TranslationEnv.t -> Type.t
    val typ_row		: TranslationEnv.t -> Type.t
    val typ_kind	: TranslationEnv.t -> Type.t
    val typ_inf		: TranslationEnv.t -> Type.t
    val typ_sig		: TranslationEnv.t -> Type.t
    val typ_ikind	: TranslationEnv.t -> Type.t
    val typ_rea		: TranslationEnv.t -> Type.t
    val typ_module	: TranslationEnv.t -> Type.t

    val lab_package	: Label.t
    val typ_package	: TranslationEnv.t * Type.t -> Type.t

    (* Translation *)

    val typToTyp	: TranslationEnv.t * Type.t -> Type.t
    val infToTyp	: TranslationEnv.t * Inf.t -> Type.t
    val clear		: unit -> unit
end
