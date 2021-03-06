val assert=General.assert;
(*
 * Author:
 *   Andreas Rossberg <rossberg@ps.uni-sb.de>
 *
 * Copyright:
 *   Andreas Rossberg, 2001-2004
 *
 * Last change:
 *   $Date: 2004-05-07 15:14:04 $ by $Author: rossberg $
 *   $Revision: 1.16 $
 *)

(*
 * Standard ML infix resolution
 *
 * Definition, section 2.6
 *)








structure Infix :> INFIX =
struct

  (* Import *)

    structure Grammar = InputGrammar
    structure E       = AbstractionError

    open Grammar

    val error = E.error


  (* Type definitions *)

    datatype Assoc = LEFT | RIGHT

    type InfStatus = (Assoc * int) option

    type InfEnv    = VId.t -> InfStatus


    (* Categorisation of atomic expressions and patterns *)

    datatype 'a FixityCategory = NONFIX of 'a
			       | INFIX  of Assoc * int * VId

    fun categoriseVId IE (at, vid as VId(i,vid')) =
	case IE vid'
	  of NONE             => NONFIX(at)
	   | SOME(assoc,prec) => INFIX(assoc, prec, vid)


    fun categoriseLongVId IE (at, SHORTLong(i, vid)) =
	    categoriseVId IE (at, vid)
      | categoriseLongVId IE (at, longvid) = NONFIX(at)

    fun categoriseAtExp IE (atexp as LONGVIDAtExp(i, SANSOp, longvid)) =
	    categoriseLongVId IE (atexp, longvid)
      | categoriseAtExp IE (atexp) = NONFIX(atexp)

    fun categoriseAtPat IE (atpat as LONGVIDAtPat(i, SANSOp, longvid)) =
	    categoriseLongVId IE (atpat, longvid)
      | categoriseAtPat IE (atpat) = NONFIX(atpat)



    (* Converting app expressions and patterns into atomic lists *)

    fun flattenExp'(ATEXPExp(i,atexp))   = atexp :: []
      | flattenExp'(APPExp(i,exp,atexp)) = atexp :: flattenExp' exp
      | flattenExp' _ = raise Crash.Crash "Infix.flattenExp: invalid expression"

    fun flattenExp exp = List.rev(flattenExp' exp)

    fun flattenPat'(ATPATPat(i,atpat))   = atpat :: []
      | flattenPat'(APPPat(i,pat,atpat)) = atpat :: flattenPat' pat
      | flattenPat' _ = raise Crash.Crash "Infix.flattenPat: invalid pattern"

    fun flattenPat pat = List.rev(flattenPat' pat)



    (* Resolving infixed expressions and patterns *)

    datatype ('a,'b) x = ATOMIC of 'a | NONATOMIC of 'b

    fun parse (ATXx, APPx, PARAtX, TUPLEAtX, LONGVIDAtX,
	       infoX, infoAtX, categorise, flatten) IE x =
	let
	    fun info(ATOMIC x)         = infoAtX x
	      | info(NONATOMIC x)      = infoX x

	    fun atomic(ATOMIC x)       = x
	      | atomic(NONATOMIC x)    = PARAtX(infoX x, x)

	    fun nonatomic(ATOMIC x)    = ATXx(infoAtX x, x)
	      | nonatomic(NONATOMIC x) = x

	    fun pair(x1,x2) =
		let
		    val x1' = nonatomic x1
		    val x2' = nonatomic x2
		in
		    TUPLEAtX(Source.span(info x1,info x2), [x1', x2'])
		end

	    fun apply(x1,x2) =
		let
		    val x1' = nonatomic x1
		    val x2' = atomic x2
		    val x'  = APPx(Source.span(info x1, info x2), x1', x2')
		in
		    NONATOMIC x'
		end

	    fun infapply(x1,vid,x2) =
		let
		    val i       = Source.span(info x1, info x2)
		    val i_vid   = infoVId vid
		    val longvid	= SHORTLong(i_vid, vid)
		    val x1'	= LONGVIDAtX(i_vid, WITHOp, longvid)
		    val x2'	= pair(x1,x2)
		    val x'      = APPx(i, ATXx(i_vid, x1'), x2')
		in
		    NONATOMIC x'
		end


	    fun loop(NONFIX(x)::[], []) = x

	      | loop(NONFIX(x2)::NONFIX(x1)::s', i) =
		    (* reduce nonfix application *)
		    loop(NONFIX(apply(x1, x2))::s', i)

	      | loop(s, NONFIX(x)::i') =
		    (* shift *)
		    loop(NONFIX(ATOMIC x)::s, i')

	      | loop(s as NONFIX(x)::[], INFIX(q)::i') =
		    (* shift *)
		    loop(INFIX(q)::s, i')

	      | loop(NONFIX(x2)::INFIX(a,p,vid)::NONFIX(x1)::s', []) =
		    (* reduce infix application *)
		    loop(NONFIX(infapply(x1, vid, x2))::s', [])

	      | loop(s as NONFIX(x2)::INFIX(a1,p1,vid1)::NONFIX(x1)::s',
		       i as INFIX(q2 as (a2,p2,vid2))::i') =
		if p1 > p2 then
		    (* reduce infix application *)
		    loop(NONFIX(infapply(x1, vid1, x2))::s', i)
		else if p1 < p2 then
		    (* shift *)
		    loop(INFIX(q2)::s, i')
		else if a1 <> a2 then
		    let
		        val VId(i1,vid1') = vid1
		        val VId(i2,vid2') = vid2
		    in
			error(Source.span(i1,i2), E.AssocConflict(vid1',vid2'))
		    end
		else if a1 = LEFT then
		    (* reduce infix application *)
		    loop(NONFIX(infapply(x1, vid1, x2))::s', i)
		else (* a1 = RIGHT *)
		    (* shift *)
		    loop(INFIX(q2)::s, i')

	      | loop(INFIX(a,p,VId(i,vid'))::s', []) =
		    error(i, E.InfixMisplaced vid')

	      | loop(INFIX(x)::s', INFIX(a,p,VId(i,vid'))::i') =
		    error(i, E.InfixMisplaced vid')

	      | loop([], INFIX(a,p,VId(i,vid'))::i') =
		    error(i, E.InfixMisplaced vid')

	      | loop _ = raise Crash.Crash "Infix.parse: inconsistency"

	    val x' = loop([], List.map (categorise IE) (flatten x))
	in
	    nonatomic x'
	end


    (* Expressions *)

    val exp = parse(ATEXPExp, APPExp, PARAtExp, TUPLEAtExp, LONGVIDAtExp,
		    infoExp, infoAtExp, categoriseAtExp, flattenExp)

    (* Patterns *)

    val pat = parse(ATPATPat, APPPat, PARAtPat, TUPLEAtPat, LONGVIDAtPat,
		    infoPat, infoAtPat, categoriseAtPat, flattenPat)

end
