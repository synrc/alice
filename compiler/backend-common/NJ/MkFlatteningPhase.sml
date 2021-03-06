val assert=General.assert;
(*
 * Author:
 *   Leif Kornstaedt <kornstae@ps.uni-sb.de>
 *
 * Copyright:
 *   Leif Kornstaedt, 1999-2002
 *
 * Last change:
 *   $Date: 2005-08-02 13:59:45 $ by $Author: rossberg $
 *   $Revision: 1.181 $
 *)






















functor MkFlatteningPhase(structure Switches: SWITCHES) :> FLATTENING_PHASE =
    struct
	structure C = EmptyContext
	structure I = IntermediateGrammar
	structure O = FlatGrammar

	open I
	open IntermediateAux
	open SimplifyMatch

	local
	    fun lookup' (pos, (pos', idRef)::mappingRest) =
		if pos = pos' then SOME idRef
		else lookup' (pos, mappingRest)
	      | lookup' (pos, nil) = NONE
	in
	    fun lookup (pos, mapping) =
		case lookup' (pos, mapping) of
		    SOME idRef => idRef
		  | NONE => raise Crash.Crash "MkFlatteningPhase.lookup"

	    fun adjoin (pos, mapping) =
		case lookup' (pos, mapping) of
		    SOME (O.IdRef id | O.LastIdRef id) => (O.IdDef id, mapping)
		  | SOME (O.Lit _ | O.Prim _ | O.Value (_, _)) =>
			raise Crash.Crash "MkFlatteningPhase.adjoin"
		  | NONE =>
			let
			    val id = O.freshId Source.nowhere
			in
			    (O.IdDef id, (pos, O.IdRef id)::mapping)
			end
	end

	fun idRefStamp (O.IdRef (O.Id (_, stamp, _))) = stamp
	  | idRefStamp (O.LastIdRef (O.Id (_, stamp, _))) = stamp
	  | idRefStamp (O.Lit _ | O.Prim _ | O.Value (_, _)) =
	    raise Crash.Crash "MkFlatteningPhase.idRefStamp"

	fun mappingsToSubst (mapping0, mapping) =
	    List.map (fn (pos, Id (_, stamp1, _)) =>
			 (stamp1, idRefStamp (lookup (pos, mapping)))) mapping0

	fun share nil = nil
	  | share (stms as [O.SharedStm (_, _, _)]) = stms
	  | share (stms as stm::_) =
	    [O.SharedStm (O.infoStm stm, stms, Stamp.stamp ())]

	datatype continuation =
	    Decs of dec list * continuation
	  | Goto of O.body
	  | Share of O.body option ref * continuation

	(* Helper Functions for Inspecting Types *)

	fun makeArrowType (argTyp, resultTyp) =
	    case Type.inspect resultTyp of
		Type.All (var, typ) =>
		    Type.all (var, makeArrowType (argTyp, typ))
	      | _ => Type.arrow (argTyp, resultTyp)

	fun getResultType typ =
	    case Type.inspect typ of
		Type.Arrow (_, typ) => typ
	      | Type.All (_, typ) => getResultType typ
	      | _ => raise Crash.Crash "MkFlatteningPhase.getResultType"

	(* The set of pathes of abstract types known not to be product types *)
	val nonProdTypesSet =
	    let
		val set = PathSet.set ()
	    in
		Vector.app (fn path => PathSet.insert (set, path))
			   #[PervasiveType.path_int,
			     PervasiveType.path_word,
			     PervasiveType.path_real,
			     PervasiveType.path_char,
			     PervasiveType.path_string,
			     PervasiveType.path_vec,
			     PervasiveType.path_array,
			     PervasiveType.path_ref,
			     PervasiveType.path_exn];
	        set
	    end

	fun typToOutArity typ =
	    case Type.inspect typ of
		(Type.Prod _ | Type.Apply _ | Type.Unknown _ | Type.Var _) =>
		    NONE
	      | Type.Con path =>
		    if PathSet.member (nonProdTypesSet, path) then
			SOME Arity.Unary
		    else NONE
	      | (Type.Arrow _ | Type.Sum _) => SOME Arity.Unary
	      | Type.Mu typ => typToOutArity typ
	      | (Type.All _ | Type.Exist _ | Type.Lambda _) =>
		    raise Crash.Crash "MkFlatteningPhase.typToOutArity"

	(* Matching arity up with args *)

	fun testArity (args as O.OneArg _, Arity.Unary, app, body) =
	    app (args, body)
	  | testArity (O.OneArg idDef, Arity.Tuple n, app, body) =
	    let
		val ids = Vector.tabulate (n, fn _ => O.freshId Source.nowhere)
		val stm =
		    O.ValDec (Source.nowhere, idDef,
			      O.TupExp (Source.nowhere,
					Vector.map O.IdRef ids))
	    in
		app (O.TupArgs (Vector.map O.IdDef ids), stm::body)
	    end
	  | testArity (O.OneArg idDef, Arity.Product labels, app, body) =
	    let
		val labelIdVec =
		    Vector.map (fn label => (label, O.freshId Source.nowhere))
			       labels
		val labelIdDefVec =
		    Vector.map (fn (label, id) => (label, O.IdDef id))
			       labelIdVec
		val labelIdRefVec =
		    Vector.map (fn (label, id) => (label, O.IdRef id))
			       labelIdVec
		val stm =
		    O.ValDec (Source.nowhere, idDef,
			      O.ProdExp (Source.nowhere, labelIdRefVec))
	    in
		app (O.ProdArgs labelIdDefVec, stm::body)
	    end
	  | testArity (args as O.TupArgs _, Arity.Tuple _, app, body) =
	    app (args, body)
	  | testArity (args as O.ProdArgs _, Arity.Product _, app, body) =
	    app (args, body)
	  | testArity (_, _, _, _) =
	    raise Crash.Crash "MkFlatteningPhase.testArity"

	fun tagTest (labels, n, args, arity, body) =
	    testArity (args, arity,
		       fn (args, body) =>
			  O.TagTests (labels, #[(n, args, body)]), body)

	fun conTest (idRef, args, arity, body) =
	    testArity (args, arity,
		       fn (args, body) =>
			  O.ConTests #[(idRef, args, body)], body)

	fun expArity (args as O.OneArg _, Arity.Unary, _, app) =
	    (nil, app args)
	  | expArity (O.OneArg idRef, Arity.Tuple n, info: id_info, app) =
	    let
		val ids = Vector.tabulate (n, fn _ => O.freshId Source.nowhere)
	    in
		([O.TupDec (#region info, Vector.map O.IdDef ids, idRef)],
		 app (O.TupArgs (Vector.map O.IdRef ids)))
	    end
	  | expArity (O.OneArg idRef, Arity.Product labels, info, app) =
	    let
		val labelIdVec =
		    Vector.map (fn label => (label, O.freshId Source.nowhere))
			       labels
		val labelIdDefVec =
		    Vector.map (fn (label, id) => (label, O.IdDef id))
			       labelIdVec
		val labelIdRefVec =
		    Vector.map (fn (label, id) => (label, O.IdRef id))
			       labelIdVec
	    in
		([O.ProdDec (#region info, labelIdDefVec, idRef)],
		 app (O.ProdArgs labelIdRefVec))
	    end
	  | expArity (args as O.TupArgs _, Arity.Tuple _, _, app) =
	    (nil, app args)
	  | expArity (args as O.ProdArgs _, Arity.Product _, _, app) =
	    (nil, app args)
	  | expArity (_, _, _, _) =
	    raise Crash.Crash "MkFlatteningPhase.expArity"

	fun tagExp (info, labels, n, args, arity) =
	    expArity (args, arity, info,
		      fn args => O.TagExp (#region info, labels, n, args))

	fun conExp (info, id, args, arity) =
	    expArity (args, arity, info,
		      fn args => O.ConExp (#region info, id, args))

	(* Translation *)

	fun translateId (Id (info, stamp, name)) = O.Id (info, stamp, name)

	fun translateLongid (ShortId (_, id)) =
	    (nil, O.IdRef (translateId id))
	  | translateLongid (LongId (info as {region, ...},
				     longid, Lab (_, label))) =
	    let
		val (stms, idRef) = translateLongid longid
 		val id' = O.Id (info, Stamp.stamp (), Name.InId)
		val stm =
		    O.ValDec (region, O.IdDef id',
			      O.LazyPolySelExp (region, label, idRef))
	    in
		(stms @ [stm], O.IdRef id')
	    end

	fun decsToIdDefExpList (O.ValDec (_, idDef, exp')::rest, region) =
	    (idDef, exp')::decsToIdDefExpList (rest, region)
	  | decsToIdDefExpList (O.IndirectStm (_, ref bodyOpt)::rest, region) =
	    decsToIdDefExpList (valOf bodyOpt, region) @
	    decsToIdDefExpList (rest, region)
	  | decsToIdDefExpList (_::_, region) =
	    Error.error' (region, "not admissible")
	  | decsToIdDefExpList (nil, _) = nil

	val boolLabels = #[PervasiveType.lab_false, PervasiveType.lab_true]

	fun raisePrim (region, name) = [O.RaiseStm (region, O.Prim name)]

	fun translateIf (region, idRef, thenStms, elseStms) =
	    [O.TestStm (region, idRef,
			O.TagTests (boolLabels,
				    #[(1, O.TupArgs #[], thenStms),
				      (0, O.TupArgs #[], elseStms)]),
			raisePrim (region, "General.Match"))]

	fun translateCont (Decs (dec::decr, cont)) =
	    translateDec (dec, Decs (decr, cont))
	  | translateCont (Decs (nil, cont)) = translateCont cont
	  | translateCont (Goto stms) = stms
	  | translateCont (Share (ref (SOME stms), _)) = stms
	  | translateCont (Share (r, cont)) =
	    let
		val stms = share (translateCont cont)
	    in
		r := SOME stms; stms
	    end
	and translateDec (ValDec (info, VarPat (_, id as Id (_, _, name)),
				  NewExp info'), cont) =
	    O.ValDec (#region info, O.IdDef (translateId id),
		      O.NewExp (#region info', name))::translateCont cont
	  | translateDec (ValDec (info, VarPat (_, id), exp), cont) =
	    let
		fun declare exp' =
		    O.ValDec (#region info, O.IdDef (translateId id), exp')
	    in
		translateExp (exp, declare, cont)
	    end
	  | translateDec (ValDec (info as {region, ...}, pat, exp), cont) =
	    let
		val r = ref NONE
		val rest = [O.IndirectStm (region, r)]
		val (stms, idRef) = unfoldTerm (exp, Goto rest)
	    in
		if !Switches.CodeGen.debugMode andalso region <> Source.nowhere
		then
		    let
			val typ = #typ (infoExp exp)
			val matches =
			    #[(region, pat,
			       O.Exit (region, O.CondExit typ, idRef)::
			       translateCont cont)]
		    in
			r := SOME (O.Entry (region,
					    O.CondEntry (typ, idRef))::
				   simplifyCase(region, idRef, matches,
						O.Prim "General.Bind",
						true))
		    end
		else
		    let
			val matches = #[(region, pat, translateCont cont)]
		    in
			r := 
			SOME (simplifyCase (region, idRef, matches,
					    O.Prim "General.Bind",
					    true))
		    end;
		stms
	    end
	  | translateDec (RecDec (info, decs), cont) =
	    let
		val (constraints, idExpList, aliases) =
		    SimplifyRec.derec (Vector.toList decs)
		val region = #region info
		val aliasDecs =
		    List.map
			(fn (fromId, toId, info) =>
			    let
				val idDef = O.IdDef (translateId fromId)
				val idRef = O.IdRef (translateId toId)
			    in
				O.ValDec (#region info, idDef,
					  O.VarExp (#region info, idRef))
			    end) aliases
		val subst =
		    List.map (fn (Id (_, stamp1, _), Id (_, stamp2, _), _) =>
			      (stamp1, stamp2)) aliases
		val decs' =
		    List.foldr
		    (fn ((id, exp), decs) =>
		     translateExp (substExp (exp, subst),
				   fn exp' =>
				   O.ValDec (
(*--** AR: needed to add this annotation due to strange
 * bug appearing in build 3 :-( *)
#region ((infoExp: I.exp -> I.exp_info) exp),
					     O.IdDef (translateId id), exp'),
				   Goto decs)) nil idExpList
		val idDefExpList' = decsToIdDefExpList (decs', region)
		val rest =
		    O.RecDec (region, Vector.fromList idDefExpList')::
		    aliasDecs @ translateCont cont
		val errStms = share (raisePrim (region, "General.Bind"))
	    in
		List.foldr
		(fn ((longid1, longid2), rest) =>
		 let
		     val (stms1, idRef1) = translateLongid longid1
		     val (stms2, idRef2) = translateLongid longid2
		     val id1' = O.freshId region
		 in
		     stms1 @ stms2 @
		     O.ValDec (region, O.IdDef id1',
			       O.ConExp (region, idRef1, O.TupArgs #[]))::
		     [O.TestStm (region, O.IdRef id1',
				 O.ConTests #[(idRef2, O.TupArgs #[], rest)],
				 errStms)]
		 end) rest constraints
	    end
	and unfoldTerm (VarExp (_, longid), cont) =
	    let
		val (stms, idRef) = translateLongid longid
	    in
		(stms @ translateCont cont, idRef)
	    end
	  | unfoldTerm (exp, cont) =
	    let
		val info = infoExp exp
		val id' = O.freshId (#region info)
		fun declare exp' = O.ValDec (#region info, O.IdDef id', exp')
		val stms = translateExp (exp, declare, cont)
	    in
		(stms, O.IdRef id')
	    end
	and unfoldArgs (TupExp (_, exps), rest) =
	    let
		val (stms, idRefs) =
		    Vector.foldr (fn (exp, (stms, idRefs)) =>
				  let
				      val (stms', idRef) =
					  unfoldTerm (exp, Goto stms)
				  in
				      (stms', idRef::idRefs)
				  end) (rest, nil) exps
	    in
		(stms, O.TupArgs (Vector.fromList idRefs))
	    end
	  | unfoldArgs (exp as ProdExp ({typ, ...}, expFlds), rest) =
	    if Type.isUnknownRow (Type.asProd typ) then
		let
		    val (stms, idRef) = unfoldTerm (exp, Goto rest)
		in
		    (stms, O.OneArg idRef)
		end
	    else
		let
		    val (stms, labelIdRefList) =
			Vector.foldr (fn (Fld (_, Lab (_, label), exp),
					  (stms, labelIdRefList)) =>
					 let
					     val (stms', idRef) =
						 unfoldTerm (exp, Goto stms)
					 in
					     (stms', (label, idRef)::
						     labelIdRefList)
					 end) (rest, nil) expFlds
		in
		    case LabelSort.sort #1 labelIdRefList of
			(labelIdRefVec, LabelSort.Tup _) =>
			    (stms, O.TupArgs (Vector.map #2 labelIdRefVec))
		      | (labelIdRefVec, LabelSort.Prod) =>
			    (stms, O.ProdArgs labelIdRefVec)
		end
	  | unfoldArgs ((SealExp (_, exp) | UnsealExp (_, exp)), rest) =
	    unfoldArgs (exp, rest)
	  | unfoldArgs (exp, rest) =
	    let
		val (stms, idRef) = unfoldTerm (exp, Goto rest)
	    in
		(stms, O.OneArg idRef)
	    end
	and unfoldFunArgs (exp as (TupExp (_, #[_]) |
			           ProdExp (_, #[Fld (_, _, _)])), rest) =
	    let
		val (stms, idRef) = unfoldTerm (exp, Goto rest)
	    in
		(stms, O.OneArg idRef)
	    end
	  | unfoldFunArgs ((SealExp (_, exp) | UnsealExp (_, exp)), rest) =
	    unfoldFunArgs (exp, rest)
	  | unfoldFunArgs (exp, rest) = unfoldArgs (exp, rest)
	and unfoldStrict (info, exp, cont) =
	    let
		val (stms, idRef) = unfoldTerm (exp, cont)
	    in
		(O.PrimAppExp (#region info, "Future.await", #[idRef]), stms)
	    end
	and translateExp (LitExp (info, lit), f, cont) =
	    f (O.VarExp (#region info, O.Lit (translateLit (#region info, lit))))::
	    translateCont cont
	  | translateExp (PrimExp (info, name), f, cont) =
	    f (O.VarExp (#region info, O.Prim name))::translateCont cont
	  | translateExp (ImmExp (info, value), f, cont) =
	    f (O.VarExp (#region info, O.Value (value, true)))::
	    translateCont cont
	  | translateExp (NewExp info, f, cont) =
	    f (O.NewExp (#region info, Name.InId))::translateCont cont
	  | translateExp (VarExp (info, longid), f, cont) =
	    let
		val (stms, idRef) = translateLongid longid
	    in
		stms @ f (O.VarExp (#region info, idRef))::translateCont cont
	    end
	  | translateExp (TagExp (info, Lab (_, label),
				  StrictExp (info', exp)),
			  f, cont) =
	    (case typToArity (#typ (infoExp exp)) of
		 Arity.Unary =>   (* explicitly force the argument *)
		     let
			 val r = ref NONE
			 val rest = [O.IndirectStm (#region info, r)]
			 val (exp', stms) =
			     unfoldStrict (info', exp, Goto rest)
			 val id = O.freshId (#region info)
			 val stm = O.ValDec (#region info, O.IdDef id, exp')
			 val (prod, n) = labelToIndex (#typ info, label)
			 val exp'' =
			     O.TagExp (#region info, prodToLabels prod, n,
				       O.OneArg (O.IdRef id))
		     in
			 r := SOME (stm::f exp''::translateCont cont);
			 stms
		     end
	       | arity =>
		     let
			 val r = ref NONE
			 val rest = [O.IndirectStm (#region info, r)]
			 val (stms, args) = unfoldArgs (exp, rest)
			 val (prod, n) = labelToIndex (#typ info, label)
			 val (stms', exp') =
			     tagExp (info, prodToLabels prod, n, args, arity)
		     in
			 r := SOME (stms' @ f exp'::translateCont cont);
			 stms
		     end)
	  | translateExp (TagExp (info, Lab (_, label), exp), f, cont) =
	    let
		val r = ref NONE
		val rest = [O.IndirectStm (#region info, r)]
		val (stms, idRef) = unfoldTerm (exp, Goto rest)
		val (prod, n) = labelToIndex (#typ info, label)
		val exp' = O.TagExp (#region info, prodToLabels prod, n,
				     O.OneArg idRef)
	    in
		r := SOME (f exp'::translateCont cont);
		stms
	    end
	  | translateExp (ConExp (info, longid, StrictExp (info', exp)),
			  f, cont) =
	    (case typToArity (#typ (infoExp exp)) of
		 Arity.Unary =>   (* explicitly force the argument *)
		     let
			 val r = ref NONE
			 val rest = [O.IndirectStm (#region info, r)]
			 val (exp', stms2) =
			     unfoldStrict (info', exp, Goto rest)
			 val argId = O.freshId (#region info)
			 val stm = O.ValDec (#region info, O.IdDef argId, exp')
			 val (stms1, conIdRef) = translateLongid longid
			 val args = O.OneArg (O.IdRef argId)
			 val exp'' = O.ConExp (#region info, conIdRef, args)
			 val typ = #typ (infoLongid longid)
			 val entry = O.ConEntry (typ, conIdRef, args)
		     in
			 r := SOME (stm::stepPoint (info, entry, exp'',
						    O.ConExit, f, cont));
			 stms1 @ stms2
		     end
	       | arity =>
		     let
			 val r = ref NONE
			 val rest = [O.IndirectStm (#region info, r)]
			 val (stms2, args) = unfoldArgs (exp, rest)
			 val (stms1, conIdRef) = translateLongid longid
			 val (stms', exp') =
			     conExp (info, conIdRef, args, arity)
			 val typ = #typ (infoLongid longid)
			 val entry = O.ConEntry (typ, conIdRef, args)
		     in
			 r := SOME (stms' @ stepPoint (info, entry, exp',
						       O.ConExit, f, cont));
			 stms1 @ stms2
		     end)
	  | translateExp (ConExp (info, longid, exp), f, cont) =
	    let
		val r = ref NONE
		val rest = [O.IndirectStm (#region info, r)]
		val (stms2, argIdRef) = unfoldTerm (exp, Goto rest)
		val (stms1, conIdRef) = translateLongid longid
		val args = O.OneArg argIdRef
		val exp' = O.ConExp (#region info, conIdRef, args)
		val typ = #typ (infoLongid longid)
		val entry = O.ConEntry (typ, conIdRef, args)
	    in
		r := SOME (stepPoint (info, entry, exp', O.ConExit, f, cont));
		stms1 @ stms2
	    end
	  | translateExp (RefExp (info, exp), f, cont) =
	    let
		val r = ref NONE
		val rest = [O.IndirectStm (#region info, r)]
		val (stms2, idRef) = unfoldTerm (exp, Goto rest)
	    in
		(r := SOME (f (O.RefExp (#region info, idRef))::
			    translateCont cont);
		 stms2)
	    end
	  | translateExp (RollExp (_, exp), f, cont) =
	    translateExp (exp, f, cont)
	  | translateExp (StrictExp (info, exp), f, cont) =
	    let
		val r = ref NONE
		val rest = [O.IndirectStm (#region info, r)]
		val (stms, idRef) = unfoldTerm (exp, Goto rest)
		val typ = #typ (infoExp exp)
	    in
		r := SOME (stepPoint (info,
				      O.StrictEntry (typ, idRef),
				      O.PrimAppExp (#region info,
						    "Future.await", #[idRef]),
				      O.StrictExit, f, cont));
		stms
	    end
	  | translateExp (TupExp (info, exps), f, cont) =
	    let
		val r = ref NONE
		val rest = [O.IndirectStm (#region info, r)]
		val (stms, idRefs) =
		    Vector.foldr (fn (exp, (stms, idRefs)) =>
				  let
				      val (stms', idRef) =
					  unfoldTerm (exp, Goto stms)
				  in
				      (stms', idRef::idRefs)
				  end) (rest, nil) exps
	    in
		r := SOME (f (O.TupExp (#region info,
					Vector.fromList idRefs))::
			   translateCont cont);
		stms
	    end
	  | translateExp (ProdExp ({typ, region}, expFlds), f, cont) =
	    let
		val r = ref NONE
		val rest = [O.IndirectStm (region, r)]
		val (stms, fields) =
		    Vector.foldr (fn (Fld (_, Lab (_, label), exp),
				      (stms, fields)) =>
				  let
				      val (stms', idRef) =
					  unfoldTerm (exp, Goto stms)
				  in
				      (stms', (label, idRef)::fields)
				  end) (rest, nil) expFlds
		val (fields', arity) = LabelSort.sort #1 fields
		val exp' =
		    if Type.isUnknownRow (Type.asProd typ) then
			O.PolyProdExp (region, fields')
		    else
			case arity of
			    LabelSort.Tup _ =>
				O.TupExp (region, Vector.map #2 fields')
			  | LabelSort.Prod =>
				O.ProdExp (region, fields')
	    in
		r := SOME (f exp'::translateCont cont); stms
	    end
	  | translateExp (SelExp (info, Lab (_, label), exp), f, cont) =
	    let
		val r = ref NONE
		val rest = [O.IndirectStm (#region info, r)]
		val (stms2, idRef2) = unfoldTerm (exp, Goto rest)
		val (prod, n) = labelToIndex (#typ (infoExp exp), label)
		val typ = #typ (infoExp exp)
		val resTyp = #typ info
	    in
		r := SOME (stepPoint (info,
				      O.SelEntry (prod, label, n, typ, idRef2),
				      O.SelExp (#region info,
						prod, label, n, idRef2),
				      O.SelExit resTyp, f, cont));
		stms2
	    end
	  | translateExp (VecExp (info, exps), f, cont) =
	    let
		val r = ref NONE
		val rest = [O.IndirectStm (#region info, r)]
		val (stms, idRefs) =
		    Vector.foldr (fn (exp, (stms, idRefs)) =>
				  let
				      val (stms', idRef) =
					  unfoldTerm (exp, Goto stms)
				  in
				      (stms', idRef::idRefs)
				  end) (rest, nil) exps
	    in
		r := SOME (f (O.VecExp (#region info,
					Vector.fromList idRefs))::
			   translateCont cont);
		stms
	    end
	  | translateExp (FunExp (info, mats), f, cont) =
	    let
		val mats' =
		    Vector.map (fn Mat (info, pat, exp) =>
				   let
				       fun return exp' =
					   O.ReturnStm (#region info, exp')
				   in
				       (#region (infoExp exp), pat,
					translateExp (exp, return, Goto nil))
				   end) mats
		val region = #1 (Vector.sub (mats', 0))
		val errStms = raisePrim (region, "General.Match")
		val (args, graph, mapping, consequents) =
		    buildFunArgs (#region info, mats', errStms)
		val (body, _) = translateGraph (graph, mapping, #region info)
		val outArityOpt = typToOutArity (getResultType (#typ info))
	    in
		checkReachability consequents;
		f (O.FunExp (#region info, Stamp.stamp (), nil,
			     #typ info, args, outArityOpt, body))::
		translateCont cont
	    end
	  | translateExp (AppExp (info, exp1, exp2), f, cont) =
	    let
		val r = ref NONE
		val rest = [O.IndirectStm (#region info, r)]
		val (stms2, args) = unfoldFunArgs (exp2, rest)
		val (stms1, idRef1) = unfoldTerm (exp1, Goto stms2)
		val typ = #typ (infoExp exp1)
	    in
		r := SOME (stepPoint (info,
				      O.AppEntry (typ, idRef1, args),
				      O.VarAppExp (#region info, idRef1, args),
				      O.AppExit, f, cont));
		stms1
	    end
	  | translateExp (AndExp (info, exp1, exp2), f, cont) =
	    let
		val region = #region info
		val argTyp = Type.tuple #[]
		val strictTyp = Type.apply (PervasiveType.typ_strict, argTyp)
		val exp3 =
		    TagExp (info, Lab ({region = region},
				       PervasiveType.lab_false),
			    StrictExp ({region = region, typ = strictTyp},
				       TupExp ({region = region, typ = argTyp},
					       #[])))
	    in
		translateExp (IfExp (info, exp1, exp2, exp3), f, cont)
	    end
	  | translateExp (OrExp (info, exp1, exp2), f, cont) =
	    let
		val region = #region info
		val argTyp = Type.tuple #[]
		val strictTyp = Type.apply (PervasiveType.typ_strict, argTyp)
		val exp3 =
		    TagExp (info, Lab ({region = region},
				       PervasiveType.lab_true),
			    StrictExp ({region = region, typ = strictTyp},
				       TupExp ({region = region, typ = argTyp},
					       #[])))
	    in
		translateExp (IfExp (info, exp1, exp3, exp2), f, cont)
	    end
	  | translateExp (IfExp (info as {region, typ}, exp1, exp2, exp3),
			  f, cont) =
	    if !Switches.CodeGen.debugMode andalso region <> Source.nowhere
	    then
		let
		    val r = ref NONE
		    val rest = [O.IndirectStm (region, r)]
		    val (stms, arbiterIdRef) = unfoldTerm (exp1, Goto rest)
		    val r' = ref NONE
		    val rest' = [O.IndirectStm (region, r')]
		    val resId = O.freshId region
		    fun f' exp' = O.ValDec (region, O.IdDef resId, exp')
		    val cont' = Share (ref NONE, Goto rest')
		    val stms2 = translateExp (exp2, f', cont')
		    val stms3 = translateExp (exp3, f', cont')
		    val argTyp = #typ (infoExp exp1)
		in
		    r := SOME (O.Entry (region,
					O.CondEntry (argTyp, arbiterIdRef))::
			       translateIf (region, arbiterIdRef,
					    stms2, stms3));
		    r' := SOME (O.Exit (region, O.CondExit typ,
					O.IdRef resId)::
				f (O.VarExp (region, O.IdRef resId))::
				translateCont cont);
		    stms
		end
	    else
		let
		    val cont' = Share (ref NONE, cont)
		    val stms2 = translateExp (exp2, f, cont')
		    val stms3 = translateExp (exp3, f, cont')
		in
		    simplifyIf (exp1, stms2, stms3)
		end
	  | translateExp (SeqExp (_, exp1, exp2), f, cont) =
	    let
		val stms2 = translateExp (exp2, f, cont)
		fun eval exp' =
		    O.ValDec (#region (infoExp exp1), O.Wildcard, exp')
	    in
		translateExp (exp1, eval, Goto stms2)
	    end
	  | translateExp (CaseExp (info as {region, typ}, exp, mats),
			  f, cont) =
	    let
		val r = ref NONE
		val rest = [O.IndirectStm (region, r)]
		val (stms, idRef) = unfoldTerm (exp, Goto rest)
	    in
		if !Switches.CodeGen.debugMode andalso region <> Source.nowhere
		then
		    let
			val r' = ref NONE
			val rest' = [O.IndirectStm (region, r')]
			val cont' = Share (ref NONE, Goto rest')
			val resId = O.freshId region
			val resIdRef = O.IdRef resId
			fun f' exp' = O.ValDec (region, O.IdDef resId, exp')
			val matches =
			    Vector.map (fn Mat (_, pat, exp) =>
					   (#region (infoExp exp), pat,
					    translateExp (exp, f', cont')))
				       mats
			val argTyp = #typ (infoExp exp)
		    in
			r := 
			SOME (O.Entry (region,
				       O.CondEntry (argTyp, idRef))::
			      simplifyCase(region, idRef, matches,
					   O.Prim "General.Match", 
					   true));
			r' := SOME (O.Exit (region, O.CondExit typ, resIdRef)::
				    f (O.VarExp (region, resIdRef))::
				    translateCont cont)
		    end
		else
		    let
			val cont' = Share (ref NONE, cont)
			val matches =
			    Vector.map (fn Mat (_, pat, exp) =>
					   (#region (infoExp exp), pat,
					    translateExp (exp, f, cont'))) mats
		    in
			r := 
			SOME (simplifyCase (region, idRef, matches,
					    O.Prim "General.Match", 
					    true))
		    end;
		stms
	    end
	  | translateExp (RaiseExp (info, exp), _, _) =
	    let
		val r = ref NONE
		val rest = [O.IndirectStm (#region info, r)]
		val (stms, idRef) = unfoldTerm (exp, Goto rest)
		val region = #region info
	    in
		if !Switches.CodeGen.debugMode andalso region <> Source.nowhere
		then r := SOME ([O.Entry (region, O.RaiseEntry idRef),
				 O.RaiseStm (region, idRef)])
		else r := SOME [O.RaiseStm (region, idRef)];
		stms
	    end
	  | translateExp (HandleExp (info as {region, typ}, exp, mats),
			  f, cont) =
	    let
		val resId = O.freshId region
		val contBody = share (f (O.VarExp (region, O.IdRef resId))::
				      translateCont cont)
		fun f' exp' = O.ValDec (region, O.IdDef resId, exp')
		val tryCont = Goto [O.EndTryStm (region, contBody)]
		val tryBody = translateExp (exp, f', tryCont)
		val packageId = O.freshId region
		val exnId = O.freshId region
		val exnIdRef = O.IdRef exnId
	    in
		if !Switches.CodeGen.debugMode andalso region <> Source.nowhere
		then
		    let
			val handleCont =
			    Goto [O.Exit (region, O.HandleExit typ,
					  O.IdRef resId),
				  O.EndHandleStm (region, contBody)]
			val matches' =
			    Vector.map
				(fn Mat (_, pat, exp) =>
				    (#region (infoExp exp), pat,
				     translateExp (exp, f', handleCont))) mats
			val handleBody =
			    O.Entry (region, O.HandleEntry (O.IdRef exnId))::
			    simplifyCase (region, exnIdRef, matches', 
					  exnIdRef, false)
		    in
			[O.TryStm (region, tryBody, O.IdDef packageId,
				   O.IdDef exnId, handleBody)]
		    end
		else
		    let
			val handleCont =
			    Goto [O.EndHandleStm (region, contBody)]
			val matches' =
			    Vector.map
				(fn Mat (_, pat, exp) =>
				    (#region (infoExp exp), pat,
				     translateExp (exp, f', handleCont))) mats
			val handleBody =
			    simplifyCase (region, exnIdRef, matches', exnIdRef,
					  false)
		    in
			[O.TryStm (region, tryBody, O.IdDef packageId,
				   O.IdDef exnId, handleBody)]
		    end
	    end
	  | translateExp (FailExp info, f, cont) =
	    if !Switches.Language.silentFailExp then
		f (O.TupExp (#region info, #[]))::translateCont cont
	    else f (O.FailExp (#region info))::translateCont cont
	  | translateExp (LazyExp (_, exp as VarExp (_, _)), f, cont) =
	    translateExp (exp, f, cont)
	  | translateExp (LazyExp (info, SealExp (_, exp)), f, cont) =
	    translateExp (LazyExp (info, exp), f, cont)
	  | translateExp (LazyExp (info, UnsealExp (_, exp)), f, cont) =
	    translateExp (LazyExp (info, exp), f, cont)
	  | translateExp (LazyExp (info as {region, typ}, exp), f, cont) =
	    let
		val r = ref NONE
		val rest = [O.IndirectStm (region, r)]
		val funInfo = {region = region,
			       typ = makeArrowType (Type.tuple #[], typ)}
		val pat = JokPat {region = region, typ = Type.tuple #[]}
		val funExp =
		    FunExp (funInfo, #[Mat ({region = region}, pat, exp)])
		val (stms, idRef) = unfoldTerm (funExp, Goto rest)
	    in
		(r := SOME (f (O.PrimAppExp (#region info, "Future.byneed",
					     #[idRef]))::translateCont cont);
		 stms)
	    end
	  | translateExp (SpawnExp (_, exp as VarExp (_, _)), f, cont) =
	    translateExp (exp, f, cont)
	  | translateExp (SpawnExp (info, SealExp (_, exp)), f, cont) =
	    translateExp (SpawnExp (info, exp), f, cont)
	  | translateExp (SpawnExp (info, UnsealExp (_, exp)), f, cont) =
	    translateExp (SpawnExp (info, exp), f, cont)
	  | translateExp (SpawnExp (info as {region, typ}, exp), f, cont) =
	    let
		val r = ref NONE
		val rest = [O.IndirectStm (region, r)]
		val funInfo = {region = region,
			       typ = makeArrowType (Type.tuple #[], typ)}
		val pat = JokPat {region = region, typ = Type.tuple #[]}
		val funExp =
		    FunExp (funInfo, #[Mat ({region = region}, pat, exp)])
		val (stms, idRef) = unfoldTerm (funExp, Goto rest)
	    in
		r := SOME (stepPoint (info,
				      O.SpawnEntry,
				      O.PrimAppExp (#region info,
						    "Future.concur", #[idRef]),
				      O.SpawnExit typ, f, cont));
		stms
	    end
	  | translateExp (LetExp (_, decs, exp), f, cont) =
	    let
		val stms = translateExp (exp, f, cont)
	    in
		translateCont (Decs (Vector.toList decs, Goto stms))
	    end
	  | translateExp (SealExp (_, exp), f, cont) =
	    translateExp (exp, f, cont)
	  | translateExp (UnsealExp (_, exp), f, cont) =
	    translateExp (exp, f, cont)
	and simplifyIf (AndExp (_, exp1, exp2), thenStms, elseStms) =
	    let
		val elseStms' = share elseStms
		val thenStms' = simplifyIf (exp2, thenStms, elseStms')
	    in
		simplifyIf (exp1, thenStms', elseStms')
	    end
	  | simplifyIf (OrExp (_, exp1, exp2), thenStms, elseStms) =
	    let
		val thenStms' = share thenStms
		val elseStms' = simplifyIf (exp2, thenStms', elseStms)
	    in
		simplifyIf (exp1, thenStms', elseStms')
	    end
	  | simplifyIf (exp, thenStms, elseStms) =
	    let
		val info = infoExp exp
		val r = ref NONE
		val rest = [O.IndirectStm (#region info, r)]
		val (stms, idRef) = unfoldTerm (exp, Goto rest)
	    in
		r := SOME (translateIf (#region info, idRef,
					thenStms, elseStms));
		stms
	    end
	and checkReachability consequents =
	    List.app (fn (region, ref bodyOpt) =>
		      Error.warn' (Option.isNone bodyOpt, region,
				   "unreachable expression"))
	    consequents
 	and simplifyCase (region, idRef, matches, raiseIdRef, check) =
	    let
		val errStms = [O.RaiseStm (region, raiseIdRef)]
 		val (graph, consequents) =
		    buildGraph (region, matches, errStms, check)
		val (body, _) = translateGraph (graph, [(nil, idRef)], region)
	    in
		checkReachability consequents;
		body
	    end
	and translateGraph (Node (pos, test, ref thenGraph, ref elseGraph,
				  status as ref (Cooked {...})),
			    mapping, region) =
	    let
		val (body, mapping') =
		    translateNode (pos, test, thenGraph, elseGraph,
				   mapping, region)
		val stms = share body
	    in
		status := Translated stms; (stms, mapping')
	    end
	  | translateGraph (Node (_, _, _, _, ref (Translated stms)),
			    mapping, _) =
	    (stms, mapping)
	  | translateGraph (Leaf (stms, stmsOptRef as ref NONE), mapping, _) =
	    let
		val stms' = share stms
	    in
		stmsOptRef := SOME stms'; (stms', mapping)
	    end
	  | translateGraph (Leaf (_, ref (SOME stms)), mapping, _) =
	    (stms, mapping)
	  | translateGraph (Unreachable graph, mapping, region) =
	    translateGraph (graph, mapping, region)
	  | translateGraph (_, _, _) =
	    raise Crash.Crash "MkFlatteningPhase.translateGraph"
	and translateNode (pos, RefTest stamp, thenGraph, _, mapping, region) =
	    let
		val (idDef, mapping') =
		    adjoin (REF stamp::pos, mapping)
		val idRef = lookup (pos, mapping)
		val (thenBody, mapping'') =
		    translateGraph (thenGraph, mapping', region)
	    in
		(O.RefDec (region, idDef, idRef)::thenBody, mapping'')
	    end
	  | translateNode (pos, TupTest n, thenGraph, _, mapping, region) =
	    let
		val (idDefs, mapping') = translateTupArgs (n, pos, mapping)
		val idRef = lookup (pos, mapping)
		val (thenBody, mapping'') =
		    translateGraph (thenGraph, mapping', region)
	    in
		(O.TupDec (region, idDefs, idRef)::thenBody, mapping'')
	    end
	  | translateNode (pos, ProdTest labels, thenGraph, _,
			   mapping, region) =
	    let
		val (labelIdDefList, mapping') =
		    translateProdArgs (labels, pos, mapping)
		val idRef = lookup (pos, mapping)
		val (thenBody, mapping'') =
		    translateGraph (thenGraph, mapping', region)
	    in
		(O.ProdDec (region, labelIdDefList, idRef)::thenBody,
		 mapping'')
	    end
	  | translateNode (_, GuardTest (_, mapping0, exp),
			   thenGraph, elseGraph, mapping, region) =
	    let
		val info = infoExp exp
		val r = ref NONE
		val rest = [O.IndirectStm (#region info, r)]
		val subst = mappingsToSubst (mapping0, mapping)
		val (stms, idRef) =
		    unfoldTerm (substExp (exp, subst), Goto rest)
		val (thenStms, mapping') =
		    translateGraph (thenGraph, mapping, region)
		val (elseStms, mapping'') =
		    translateGraph (elseGraph, mapping', region)
	    in
		r := SOME (translateIf (#region info, idRef,
					thenStms, elseStms));
		(stms, mapping'')
	    end
	  | translateNode (_, DecTest (_, mapping0, decs),
			   thenGraph, _, mapping, region) =
	    let
		val (thenBody, mapping') =
		    translateGraph (thenGraph, mapping, region)
		val subst = mappingsToSubst (mapping0, mapping)
		val cont =
		    Decs (Vector.foldr (fn (dec, rest) =>
					substDec (dec, subst)::rest) nil decs,
			  Goto thenBody)
	    in
		(translateCont cont, mapping')
	    end
	  | translateNode (pos, LitTest lit, thenGraph, elseGraph,
			   mapping, region) =
	    let
		val idRef = lookup (pos, mapping)
		val (thenBody, mapping') =
		    translateGraph (thenGraph, mapping, region)
		val tests = O.LitTests #[(translateLit (region, lit), thenBody)]
		val (elseBody, mapping'') =
		    translateGraph (elseGraph, mapping', region)
	    in
		([O.TestStm (region, idRef, tests, elseBody)], mapping'')
	    end
	  | translateNode (pos, TagTest (labels, n, args, arity),
			   thenGraph, elseGraph, mapping, region) =
	    let
		val idRef = lookup (pos, mapping)
		val label = Vector.sub (labels, n)
		val (idDefArgs, mapping') =
		    translateArgs (args, LABEL label::pos, mapping)
		val (thenBody, mapping'') =
		    translateGraph (thenGraph, mapping', region)
		val tests = tagTest (labels, n, idDefArgs, arity, thenBody)
		val (elseBody, mapping''') =
		    translateGraph (elseGraph, mapping'', region)
	    in
		([O.TestStm (region, idRef, tests, elseBody)], mapping''')
	    end
	  | translateNode (pos, ConTest (longid, args, arity),
			   thenGraph, elseGraph, mapping, region) =
	    let
		val idRef = lookup (pos, mapping)
		val (stms, idRef') = translateLongid longid
		val (idDefArgs, mapping') =
		    translateArgs (args, longidToSelector longid::pos, mapping)
		val (thenBody, mapping'') =
		    translateGraph (thenGraph, mapping', region)
		val tests = conTest (idRef', idDefArgs, arity, thenBody)
		val (elseBody, mapping''') =
		    translateGraph (elseGraph, mapping'', region)
	    in
		(stms @ [O.TestStm (region, idRef, tests, elseBody)],
		 mapping''')
	    end
	  | translateNode (pos, VecTest n, thenGraph, elseGraph,
			   mapping, region) =
	    let
		val idRef = lookup (pos, mapping)
		val (idDefs, mapping') = translateTupArgs (n, pos, mapping)
		val (thenBody, mapping'') =
		    translateGraph (thenGraph, mapping', region)
		val tests = O.VecTests #[(idDefs, thenBody)]
		val (elseBody, mapping''') =
		    translateGraph (elseGraph, mapping'', region)
	    in
		([O.TestStm (region, idRef, tests, elseBody)], mapping''')
	    end
	and translateArgs (O.OneArg _, pos, mapping) =
	    let
		val (idDef, mapping') = adjoin (pos, mapping)
	    in
		(O.OneArg idDef, mapping')
	    end
	  | translateArgs (O.TupArgs xs, pos, mapping) =
	    let
		val (idDefs, mapping') =
		    translateTupArgs (Vector.length xs, pos, mapping)
	    in
		(O.TupArgs idDefs, mapping')
	    end
	  | translateArgs (O.ProdArgs labelXVec, pos, mapping) =
	    let
		val (labelIdDefVec, mapping') =
		    translateProdArgs (Vector.map #1 labelXVec, pos, mapping)
	    in
		(O.ProdArgs labelIdDefVec, mapping')
	    end
	and translateTupArgs (n, pos, mapping) =
	    let
		val (idDefs, mapping) =
		    if n = 0 then (nil, mapping)
		    else translateTupArgs' (1, n, pos, mapping)
	    in
		(Vector.fromList idDefs, mapping)
	    end
	and translateTupArgs' (i, n, pos, mapping) =
	    let
		val (idDefs, mapping) =
		    if i = n then (nil, mapping)
		    else translateTupArgs' (i + 1, n, pos, mapping)
		val (idDef, mapping) =
		    adjoin (LABEL (Label.fromInt i)::pos, mapping)
	    in
		(idDef::idDefs, mapping)
	    end
	and translateProdArgs (labels, pos, mapping) =
	    let
		val (labelIdDefList, mapping) =
		    Vector.foldr
		    (fn (label, (labelIdDefList, mapping)) =>
		     let
			 val (idDef, mapping) =
			     adjoin (LABEL label::pos, mapping)
		     in
			 ((label, idDef)::labelIdDefList, mapping)
		     end) (nil, mapping) labels
	    in
		(Vector.fromList labelIdDefList, mapping)
	    end
	and stepPoint (info as {region, ...}, entryPoint, exp, exitPoint,
		       f, cont) =
	    if !Switches.CodeGen.debugMode andalso region <> Source.nowhere
	    then
		let
		    val resId = O.freshId region
		in
		    O.Entry (region, entryPoint)::
		    O.ValDec (region, O.IdDef resId, exp)::
		    O.Exit (region, exitPoint, O.IdRef resId)::
		    f (O.VarExp (region, O.IdRef resId))::
		    translateCont cont
		end
	    else f exp::translateCont cont

	fun translate (desc, _, (imports, decs, idFlds, sign)) =
	    let
		val imports' =
		    Vector.map (fn (id, sign, url, compileTime) =>
				   (translateId id, sign, url, compileTime))
			       imports
		val labelIdList =
		    Vector.foldr (fn (Fld (_, Lab (_, label), id), rest) =>
				     (label, translateId id)::rest)
				 nil idFlds
		val (exports', _) = LabelSort.sort #1 labelIdList
		val labelIdRefVec =
		    Vector.map (fn (label, id) => (label, O.IdRef id)) exports'
		val exportExp = O.PolyProdExp (Source.nowhere, labelIdRefVec)
		val cont = Goto [O.ExportStm (Source.nowhere, exportExp)]
		val body' = translateCont (Decs (Vector.toList decs, cont))
	    in
		IntermediateAux.reset ();
		((), {imports = imports', body = body',
		      exports = exports', sign = sign})
	    end
    end
