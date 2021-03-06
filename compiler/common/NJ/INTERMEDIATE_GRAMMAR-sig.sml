val assert=General.assert;
(*
 * Authors:
 *   Andreas Rossberg <rossberg@ps.uni-sb.de>
 *
 * Copyright:
 *   Andreas Rossberg, 2001-2007
 *
 * Last change:
 *   $Date: 2007-04-02 14:17:20 $ by $Author: rossberg $
 *   $Revision: 1.74 $
 *)







signature INTERMEDIATE_GRAMMAR =
sig
    (* Generic *)

    type lab_info
    type id_info
    type longid_info
    type exp_info
    type pat_info
    type 'a fld_info
    type mat_info
    type dec_info

    type sign

    (* Literals *)

    datatype lit =
	  IntLit    of LargeInt.int		(* integer arithmetic *)
	| WordLit   of LargeWord.word		(* modulo arithmetic *)
	| CharLit   of WideChar.char		(* character *)
	| StringLit of WideString.string	(* character string *)
	| RealLit   of LargeReal.real		(* floating point *)

    (* Identifiers *)

    datatype lab    = Lab     of lab_info * Label.t
    datatype id     = Id      of id_info * Stamp.t * Name.t
    datatype longid = ShortId of longid_info * id
		    | LongId  of longid_info * longid * lab

    (* Expressions *)

    datatype exp =
	  LitExp    of exp_info * lit			(* literal *)
	| VarExp    of exp_info * longid		(* variable *)
	| PrimExp   of exp_info * string		(* primitive value *)
	| ImmExp    of exp_info * Reflect.value		(* immediate value *)
	| NewExp    of exp_info				(* new constructor *)
	| TagExp    of exp_info * lab * exp		(* tagged value *)
	| ConExp    of exp_info * longid * exp		(* constructed value *)
	| RefExp    of exp_info	* exp			(* reference *)
	| TupExp    of exp_info * exp vector		(* tuple *)
	| ProdExp   of exp_info * exp fld vector	(* record / module *)
				(* all labels distinct *)
	| SelExp    of exp_info * lab * exp		(* field selection *)
	| VecExp    of exp_info * exp vector		(* vector *)
	| RollExp   of exp_info * exp			(* recursive typing *)
	| StrictExp of exp_info * exp			(* strict evaluation *)
	| FunExp    of exp_info * mat vector		(* function / functor *)
	| AppExp    of exp_info * exp * exp		(* application *)
	| AndExp    of exp_info * exp * exp		(* conjunction *)
	| OrExp     of exp_info * exp * exp		(* disjunction *)
	| IfExp     of exp_info * exp * exp * exp	(* conditional *)
	| SeqExp    of exp_info * exp * exp		(* sequential *)
	| CaseExp   of exp_info * exp * mat vector	(* case switch *)
	| RaiseExp  of exp_info * exp			(* exception raise *)
	| HandleExp of exp_info * exp * mat vector	(* exception handler *)
	| FailExp   of exp_info				(* lazy failure *)
	| LazyExp   of exp_info * exp			(* by-need suspension *)
	| SpawnExp  of exp_info * exp			(* concurrent thread *)
	| LetExp    of exp_info * dec vector * exp	(* local binding *)
	| SealExp   of exp_info * exp			(* type abstraction *)
	| UnsealExp of exp_info * exp			(* type realization *)

    and 'a fld = Fld of 'a fld_info * lab * 'a

    (* Patterns (always linear) *)

    and mat = Mat of mat_info * pat * exp

    and pat =
	  JokPat    of pat_info				(* joker (wildcard) *)
	| VarPat    of pat_info * id			(* variable *)
	| LitPat    of pat_info * lit			(* literal *)
	| TagPat    of pat_info * lab * pat		(* tagged value *)
	| ConPat    of pat_info * longid * pat		(* constructed *)
	| RefPat    of pat_info * pat			(* reference *)
	| TupPat    of pat_info * pat vector		(* tuple *)
	| ProdPat   of pat_info * pat fld vector	(* record *)
				(* all labels distinct *)
	| VecPat    of pat_info * pat vector		(* vector *)
	| RollPat   of pat_info * pat			(* recursive typing *)
	| StrictPat of pat_info * pat			(* non-future *)
	| AsPat     of pat_info * pat * pat		(* conjunction *)
	| AltPat    of pat_info * pat * pat		(* disjunction *)
				(* both patterns bind same ids *)
	| NegPat    of pat_info * pat			(* negation *)
	| GuardPat  of pat_info * pat * exp		(* guard *)
	| WithPat   of pat_info * pat * dec vector	(* local bindings *)

    (* Declarations *)

    and dec =
	  ValDec    of dec_info * pat * exp		(* value / module *)
	  		(* if inside RecDec, then
			 * (1) pat may not contain AltPat, NegPat, GuardPat,
			 *     WithPat
			 * (2) exp may only contain LitExp, VarExp, ConExp,
			 *     RefExp, TupExp, RowExp, VecExp, FunExp, AppExp
			 * (3) AppExps may only contain ConExp or RefExp
			 *     as first argument
			 * (4) if an VarPat on the LHS structurally corresponds
			 *     to an VarExp on the RHS then the RHS id may not
			 *     be bound on the LHS *)
	| RecDec    of dec_info * dec vector		(* recursion *)

    (* Components *)

    type imp = id * sign * Url.t * bool (* is compile time *)
    type com = imp vector * dec vector * id fld vector * sign
    type t   = com


    (* Operations *)

    val stamp :		id	-> Stamp.t
    val name :		id	-> Name.t
    val lab :		lab	-> Label.t

    val infoLab :	lab	-> lab_info
    val infoId :	id	-> id_info
    val infoLongid :	longid	-> longid_info
    val infoExp :	exp	-> exp_info
    val infoFld :	'a fld	-> 'a fld_info
    val infoMat :	mat	-> mat_info
    val infoPat :	pat	-> pat_info
    val infoDec :	dec	-> dec_info
end
