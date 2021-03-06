val assert=General.assert;
(*
 * Author:
 *   Leif Kornstaedt <kornstae@ps.uni-sb.de>
 *
 * Copyright:
 *   Leif Kornstaedt, 1999-2001
 *
 * Last change:
 *   $Date: 2006-07-06 15:10:52 $ by $Author: rossberg $
 *   $Revision: 1.56 $
 *)













structure SimplifyRec :> SIMPLIFY_REC =
    struct
	structure I = IntermediateGrammar
	structure O = FlatGrammar

	open I
	open IntermediateAux

	type constraint = longid * longid
	type binding = id * exp
	type alias = id * id * exp_info

	datatype pat =
	    JokPat of pat_info
	  | LitPat of pat_info * lit
	  | VarPat of pat_info * id
	  | TagPat of pat_info * lab * pat
	  | ConPat of pat_info * longid * pat
	  | RefPat of pat_info * pat
	  | TupPat of pat_info * pat vector
	  | ProdPat of pat_info * pat fld vector
	  | VecPat of pat_info * pat vector
	  | AsPat of pat_info * id * pat

	fun infoPat (JokPat info) = info
	  | infoPat (LitPat (info, _)) = info
	  | infoPat (VarPat (info, _)) = info
	  | infoPat (TagPat (info, _, _)) = info
	  | infoPat (ConPat (info, _, _)) = info
	  | infoPat (RefPat (info, _)) = info
	  | infoPat (TupPat (info, _)) = info
	  | infoPat (ProdPat (info, _)) = info
	  | infoPat (VecPat (info, _)) = info
	  | infoPat (AsPat (info, _, _)) = info

	fun getFieldLabel (Fld (_, Lab (_, label), _)) = label

	fun select (Fld (_, Lab (_, s), x)::fldr, s') =
	    if s = s' then SOME x else select (fldr, s')
	  | select (nil, _) = NONE

	fun unalias (JokPat _) = (nil, NONE)
	  | unalias (VarPat (_, id)) = ([id], NONE)
	  | unalias (AsPat (_, id, pat)) =
	    let
		val (ids, patOpt) = unalias pat
	    in
		(id::ids, patOpt)
	    end
	  | unalias pat = (nil, SOME pat)

	fun mkRefTyp typ =
	    Type.arrow (typ, Type.apply (PervasiveType.typ_ref, typ))

	fun patToExp (JokPat info) =
	    let
		val id = freshIntermediateId info
	    in
		(VarPat (info, id), VarExp (info, ShortId (info, id)))
	    end
	  | patToExp (pat as LitPat (info, lit)) = (pat, LitExp (info, lit))
	  | patToExp (pat as VarPat (info, id)) =
	    (pat, VarExp (info, ShortId (info, id)))
	  | patToExp (TagPat (info, lab, pat)) =
	    let
		val (pat', exp') = patToExp pat
	    in
		(TagPat (info, lab, pat'),
		 TagExp (info, lab, exp'))
	    end
	  | patToExp (ConPat (info, longid, pat)) =
	    let
		val (pat', exp') = patToExp pat
	    in
		(ConPat (info, longid, pat'),
		 ConExp (info, longid, exp'))
	    end
	  | patToExp (RefPat (info, pat)) =
	    let
		val (pat', exp') = patToExp pat
		val info' =
		    {region = #region info,
		     typ = mkRefTyp (#typ (infoPat pat))}
	    in
		(RefPat (info, pat'), RefExp (info, exp'))
	    end
	  | patToExp (TupPat (info, pats)) =
	    let
		val (pats', exps') =
		    VectorPair.unzip (Vector.map patToExp pats)
	    in
		(TupPat (info, pats'), TupExp (info, exps'))
	    end
	  | patToExp (ProdPat (info, patFlds)) =
	    let
		val (patFlds', expFlds') =
		    Vector.foldr (fn (Fld (info, label, pat),
				      (patFlds, expFlds)) =>
				  let
				      val (pat', exp) = patToExp pat
				  in
				      (Fld (info, label, pat')::patFlds,
				       Fld (info, label, exp)::expFlds)
				  end) (nil, nil) patFlds
	    in
		(ProdPat (info, Vector.fromList patFlds'),
		 ProdExp (info, Vector.fromList expFlds'))
	    end
	  | patToExp (VecPat (info, pats)) =
	    let
		val (pats', exps') =
		    VectorPair.unzip (Vector.map patToExp pats)
	    in
		(VecPat (info, pats'), VecExp (info, exps'))
	    end
	  | patToExp (pat as AsPat (info, id, _)) =
	    (pat, VarExp (info, ShortId (info, id)))

	fun derec' (JokPat _, exp) = (nil, [(nil, exp)])
	  | derec' (LitPat (info, lit1), LitExp (_, lit2)) =
	    if litEq (lit1, lit2) then (nil, nil)
	    else Error.error' (#region info, "pattern never matches")
	  | derec' (VarPat (_, id), exp) = (nil, [([id], exp)])
	  | derec' (TagPat (info, Lab (_, label1), pat),
		    TagExp (_, Lab (_, label2), exp)) =
	    let
		val (constraints, idsExpList) = derec' (pat, exp)
	    in
		if label1 = label2 then (constraints, idsExpList)
		else Error.error' (#region info, "pattern never matches")
	    end
	  | derec' (ConPat (_, longid1, pat),
		    ConExp (_, longid2, exp)) =
	    let
		val (constraints, idsExpList) = derec' (pat, exp)
	    in
		((longid1, longid2)::constraints, idsExpList)
	    end
	  | derec' (RefPat (_, pat), AppExp (_, RefExp _, exp)) =
	    derec' (pat, exp)
	  | derec' (TupPat (_, pats), TupExp (_, exps)) =
	    VectorPair.foldr (fn (pat, exp, (cr, idsExpr)) =>
			      let
				  val (cs, idsExps) = derec' (pat, exp)
			      in
				  (cs @ cr, idsExps @ idsExpr)
			      end) (nil, nil) (pats, exps)
	  | derec' (TupPat (_, pats), ProdExp (_, expFlds)) =
	    (case LabelSort.sort getFieldLabel (Vector.toList expFlds) of
		 (expFlds', LabelSort.Tup _) =>
		     VectorPair.foldr
		     (fn (pat, Fld (_, _, exp), (cr, idsExpr)) =>
		      let
			  val (cs, idsExps) = derec' (pat, exp)
		      in
			  (cs @ cr, idsExps @ idsExpr)
		      end) (nil, nil) (pats, expFlds')
	       | (_, LabelSort.Prod) =>
		     raise Crash.Crash
			 "SimplifyRec.derec' 1 type inconsistency")
	  | derec' (ProdPat (_, _), TupExp (_, _)) =
	    raise Crash.Crash "SimplifyRec.derec' 2 type inconsistency"
	  | derec' (ProdPat (_, patFlds), ProdExp (_, expFlds)) =
	    let
		val (expFlds', _) =
		    LabelSort.sort getFieldLabel (Vector.toList expFlds)
	    in
		VectorPair.foldr
		(fn (Fld (_, _, pat), Fld (_, _, exp), (cr, idsExpr)) =>
		 let
		     val (cs, idsExps) = derec' (pat, exp)
		 in
		     (cs @ cr, idsExpr @ idsExpr)
		 end) (nil, nil) (patFlds, expFlds')
	    end
	  | derec' (VecPat (_, pats), VecExp (_, exps)) =
	    VectorPair.foldr (fn (pat, exp, (cr, idsExpr)) =>
			      let
				  val (cs, idsExps) = derec' (pat, exp)
			      in
				  (cs @ cr, idsExps @ idsExpr)
			      end) (nil, nil) (pats, exps)
	  | derec' (pat as AsPat (_, _, _), exp) =
	    let
		val (ids, patOpt) = unalias pat
	    in
		case patOpt of
		    NONE =>
			(nil, [(ids, exp)])
		  | SOME pat' =>
			let
			    val (pat'', exp') = patToExp pat'
			    val (constraints, idsExpList) = derec' (pat'', exp)
			in
			    (constraints, (ids, exp')::idsExpList)
			end
	    end
	  | derec' (_, _) =
	    raise Crash.Crash "SimplifyRec.derec' 3 internal error"

	fun unify (JokPat _, pat2) = (nil, pat2)
	  | unify (pat1, JokPat _) = (nil, pat1)
	  | unify (pat1 as LitPat (info, lit1), LitPat (_, lit2)) =
	    if litEq (lit1, lit2) then (nil, pat1)
	    else Error.error' (#region info, "pattern never matches")
	  | unify (VarPat (info, id), pat2) = (nil, AsPat (info, id, pat2))
	  | unify (pat1, VarPat (info, id)) = (nil, AsPat (info, id, pat1))
	  | unify (TagPat (info, lab as Lab (_, label), pat1),
		   TagPat (_, Lab (_, label'), pat2)) =
	    let
		val (constraints, pat) = unify (pat1, pat2)
	    in
		if label = label' then
		    (constraints, TagPat (info, lab, pat))
		else Error.error' (#region info, "pattern never matches")
	    end
	  | unify (ConPat (info, longid, pat1),
		   ConPat (_, longid', pat2)) =
	    let
		val (constraints, pat) = unify (pat1, pat2)
	    in
		((longid, longid')::constraints,
		 ConPat (info, longid, pat))
	    end
	  | unify (RefPat (info, pat1), RefPat (_, pat2)) =
	    let
		val (constraints, pat) = unify (pat1, pat2)
	    in
		(constraints, RefPat (info, pat))
	    end
	  | unify (TupPat (info, pats1), TupPat (_, pats2)) =
	    let
		val (constraints, pats) =
		    VectorPair.foldr (fn (pat1, pat2, (cr, patr)) =>
				      let
					  val (cs, pat) = unify (pat1, pat2)
				      in
					  (cs @ cr, pat::patr)
				      end) (nil, nil) (pats1, pats2)
	    in
		(constraints, TupPat (info, Vector.fromList pats))
	    end
	  | unify (ProdPat (info, patFlds1), ProdPat (_, patFlds2)) =
	    let
		val (constraints, patFlds) =
		    VectorPair.foldr
		    (fn (Fld (info, label, pat1),
			 Fld (_, _, pat2), (cr, patFldr)) =>
		     let
			 val (cs, pat) = unify (pat1, pat2)
		     in
			 (cs @ cr,
			  Fld (info, label, pat)::patFldr)
		     end) (nil, nil) (patFlds1, patFlds2)
	    in
		(constraints, ProdPat (info, Vector.fromList patFlds))
	    end
	  | unify (VecPat (info, pats1), VecPat (_, pats2)) =
	    if Vector.length pats1 = Vector.length pats2 then
		let
		    val (constraints, pats) =
			VectorPair.foldr
			(fn (pat1, pat2, (cr, patr)) =>
			 let
			     val (cs, pat) = unify (pat1, pat2)
			 in
			     (cs @ cr, pat::patr)
			 end) (nil, nil) (pats1, pats2)
		in
		    (constraints, VecPat (info, Vector.fromList pats))
		end
	    else Error.error' (#region info, "pattern never matches")
	  | unify (AsPat (info, id, pat1), pat2) =
	    let
		val (constraints, pat) = unify (pat1, pat2)
	    in
		(constraints, AsPat (info, id, pat))
	    end
	  | unify (pat1, pat2 as AsPat (_, _, _)) = unify (pat2, pat1)
	  | unify (pat, _) =
	    Error.error' (#region (infoPat pat), "pattern never matches")

	fun parseRow row =
	    case Type.inspectRow row of
		(Type.EmptyRow | Type.UnknownRow _) => nil
	      | Type.FieldRow (label, typ, row') => (label, typ)::parseRow row'

	fun getField (Fld (_, _, pat)) = pat

	fun preprocess (I.JokPat info) = (nil, JokPat info)
	  | preprocess (I.LitPat (info, lit)) = (nil, LitPat (info, lit))
	  | preprocess (I.VarPat (info, id)) = (nil, VarPat (info, id))
	  | preprocess (I.TagPat (info, label, pat)) =
	    let
		val (constraints, pat') = preprocess pat
	    in
		(constraints, TagPat (info, label, pat'))
	    end
	  | preprocess (I.ConPat (info, longid, pat)) =
	    let
		val (constraints, pat') = preprocess pat
	    in
		(constraints, ConPat (info, longid, pat'))
	    end
	  | preprocess (I.RefPat (info, pat)) =
	    let
		val (constraints, pat') = preprocess pat
	    in
		(constraints, RefPat (info, pat'))
	    end
	  | preprocess (I.RollPat (_, pat)) = preprocess pat
	  | preprocess (I.StrictPat (_, pat)) = preprocess pat
	  | preprocess (I.TupPat (info, pats)) =
	    let
		val (constraints, pats) =
		    Vector.foldr (fn (pat, (cr, patr)) =>
				  let
				      val (cs, pat) = preprocess pat
				  in
				      (cs @ cr, pat::patr)
				  end) (nil, nil) pats
	    in
		(constraints, TupPat (info, Vector.fromList pats))
	    end
	  | preprocess (I.ProdPat (info, patFlds)) =
	    let
		val row = Type.asProd (#typ info)
		val labelTypList =
		    if Type.isTupleRow row then
			Vector.foldri (fn (i, typ, rest) =>
				       (Label.fromInt (i + 1), typ)::rest)
			nil (Type.asTupleRow row)
		    else parseRow row
		fun adjoin (labelTyp as (label, _), patFlds as
			    (Fld (_, Lab (_, label'), _)::rest)) =
		    if label = label' then patFlds
		    else adjoin (labelTyp, rest)
		  | adjoin ((label, typ), nil) =
		    let
			val info = {region = Source.nowhere}
		    in
			[Fld (info, Lab (info, label),
			      I.JokPat {region = Source.nowhere, typ = typ})]
		    end
		val patFlds' =
		    List.foldr adjoin (Vector.toList patFlds) labelTypList
		val (patFlds'', arity) = LabelSort.sort getFieldLabel patFlds'
		val (constraints, patFlds''') =
		    Vector.foldr
		    (fn (Fld (info, label, pat), (cr, fldr)) =>
		     let
			 val (cs, pat') = preprocess pat
		     in
			 (cs @ cr, Fld (info, label, pat')::fldr)
		     end) (nil, nil) patFlds''
		val patFlds'''' = Vector.fromList patFlds'''
		val pat' =
		    case arity of
			LabelSort.Tup i =>
			    TupPat (info, Vector.map getField patFlds'''')
		      | LabelSort.Prod =>
			    ProdPat (info, patFlds'''')
	    in
		(constraints, pat')
	    end
	  | preprocess (I.VecPat (info, pats)) =
	    let
		val (constraints, pats) =
		    Vector.foldr (fn (pat, (cr, patr)) =>
				  let
				      val (cs, pat) = preprocess pat
				  in
				      (cs @ cr, pat::patr)
				  end) (nil, nil) pats
	    in
		(constraints, VecPat (info, Vector.fromList pats))
	    end
	  | preprocess (I.AsPat (_, pat1, pat2)) =
	    let
		val (constraints1, pat1') = preprocess pat1
		val (constraints2, pat2') = preprocess pat2
		val (constraints3, pat') = unify (pat1', pat2')
	    in
		(constraints1 @ constraints2 @ constraints3, pat')
	    end
	  | preprocess (I.AltPat (info, _, _)) =
	    Error.error' (#region info,
			  "alternative pattern not allowed in val rec")
	  | preprocess (I.NegPat (info, _)) =
	    Error.error' (#region info,
			  "negated pattern not allowed in val rec")
	  | preprocess (I.GuardPat (info, _, _)) =
	    Error.error' (#region info,
			  "guard pattern not allowed in val rec")
	  | preprocess (I.WithPat (info, _, _)) =
	    Error.error' (#region info,
			  "with pattern not allowed in val rec")

	fun derec (ValDec (_, pat, exp)::decr) =
	    let
		val (constraints, pat') = preprocess pat
		val (constraints', idsExpList) = derec' (pat', exp)
		val (idExpList, aliases) =
		    List.foldr (fn ((ids, exp), (rest, subst)) =>
				let
				    val toId = List.hd ids
				    val info = infoExp exp
				in
				    ((toId, exp)::rest,
				     List.foldr
				     (fn (fromId, subst) =>
				      (fromId, toId, info)::subst)
				     subst (List.tl ids))
				end) (nil, nil) idsExpList
		val (constraints'', idExpList', aliases') = derec decr
	    in
		(constraints @ constraints' @ constraints'',
		 idExpList @ idExpList', aliases @ aliases')
	    end
	  | derec (RecDec (_, decs)::decr) =
	    let
		val (constraints, idExpList, aliases) =
		    derec (Vector.toList decs)
		val (constraints', idExpList', aliases') = derec decr
	    in
		(constraints @ constraints',
		 idExpList @ idExpList', aliases @ aliases')
	    end
	  | derec nil = (nil, nil, nil)
    end
