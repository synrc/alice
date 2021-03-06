val assert=General.assert;
(*
 * Author:
 *   Andreas Rossberg <rossberg@ps.uni-sb.de>
 *
 * Copyright:
 *   Andreas Rossberg, 2001-2004
 *
 * Last change:
 *   $Date: 2007-02-13 14:56:34 $ by $Author: rossberg $
 *   $Revision: 1.26 $
 *)















structure AbstractionError :> ABSTRACTION_ERROR =
struct
  (* Pretty printer *)

    open PrettyPrint
    open PPMisc

    infixr ^^ ^/^

  (* Types *)

    datatype error =
	(* Infix *)
	  InfixMisplaced	of VId.t
	| AssocConflict		of VId.t * VId.t
	(* Identifiers *)
	| VIdUnbound		of VId.t
	| TyConUnbound		of TyCon.t
	| TyVarUnbound		of TyVar.t
	| StrIdUnbound		of StrId.t
	| SigIdUnbound		of SigId.t
	| LongStrIdNonStruct
	| ConTyConShadowed	of TyCon.t * VId.t
	(* Expressions *)
	| ExpConArgSuperfluous
	| ExpRowLabDuplicate	of Lab.t
	(* Patterns *)
	| PatConArgMissing
	| PatConArgSuperfluous
	| PatVIdDuplicate	of VId.t
	| WithPatVIdDuplicate	of VId.t
	| PatLongVIdVar
	| PatRowLabDuplicate	of Lab.t
	| AppPatNonCon
	| AltPatInconsistent
	(* Types *)
	| TyRowLabDuplicate	of Lab.t
	| TyVarSeqDuplicate	of TyVar.t
	| ValTyVarSeqDuplicate	of TyVar.t
	(* Declarations and bindings *)
	| OpenDecNonStruct
	| ReplicationDecConShadowed of VId.t
	| FvalBindDuplicate	of VId.t
	| FvalBindArityInconsistent
	| FvalBindArityZero
	| FvalBindNameInconsistent of VId.t
	| FvalBindNameMissing
	| FvalBindNameCon	of VId.t
	| FvalBindPatInvalid
	| TypBindDuplicate	of TyCon.t
	| DatBindDuplicate	of TyCon.t
	| DatBindConDuplicate	of VId.t
	| ConBindDuplicate	of VId.t
	| ExtBindDuplicate	of TyCon.t
	| EconBindDuplicate	of VId.t
	| EconBindNonCon
	| StrBindDuplicate	of StrId.t
	| SigBindDuplicate	of SigId.t
	(* Structure expressions *)
	| AppStrExpNonFun
	(* Specifications and descriptions *)
	| IncludeSpecNonStruct
	| ReplicationSpecConShadowed of VId.t
	| SpecFixDuplicate	of VId.t
	| SpecVIdDuplicate	of VId.t
	| SpecTyConDuplicate	of TyCon.t
	| SpecStrIdDuplicate	of StrId.t
	| SpecSigIdDuplicate	of SigId.t
	| ConDescDuplicate	of VId.t
	| EconDescNonCon
	(* Imports and items *)
	| ImpFixDuplicate	of VId.t
	| ImpVIdDuplicate	of VId.t
	| ImpTyConDuplicate	of TyCon.t
	| ImpStrIdDuplicate	of StrId.t
	| ImpSigIdDuplicate	of SigId.t
	| ConItemDuplicate	of VId.t
	| ValItemUnbound	of VId.t
	| TypItemUnbound	of TyCon.t
	| DatItemUnbound	of TyCon.t
	| ConItemUnbound	of VId.t
	| ExtItemUnbound	of TyCon.t
	| EconItemUnbound	of VId.t
	| StrItemUnbound	of StrId.t
	| SigItemUnbound	of SigId.t
	| ConItemNonCon		of VId.t
	| EconItemNonCon	of VId.t
	(* Sharing translation *)
	| SharingExternalTy	of AbstractGrammar.typid
	| SharingExternalSig	of AbstractGrammar.infid
	| SharingExternalStr	of AbstractGrammar.modid

    datatype warning =
	(* Shadowing *)
	  VIdShadowed		of VId.t
	| TyConShadowed		of TyCon.t
	| TyVarShadowed		of TyVar.t
	| StrIdShadowed		of StrId.t
	| SigIdShadowed		of SigId.t
	(* Conventions *)
	| LabConvention		of Lab.t
	| VIdConvention		of VId.t
	| ValVIdConvention	of VId.t
	| ConVIdConvention	of VId.t
	| TyConConvention	of TyCon.t
	| TyVarConvention	of TyVar.t
	| StrIdConvention	of StrId.t
	| SigIdConvention	of SigId.t


  (* Pretty printing *)

    fun ppQuoted s	= "`" ^ s ^ "'"

    fun ppLab lab	= ppQuoted(Lab.toString lab)
    fun ppVId vid	= ppQuoted(VId.toString vid)
    fun ppTyCon tycon	= ppQuoted(TyCon.toString tycon)
    fun ppTyVar tyvar	= ppQuoted(TyVar.toString tyvar)
    fun ppStrId strid	= ppQuoted(StrId.toString strid)
    fun ppSigId sigid	= ppQuoted(SigId.toString sigid)

    fun ppLab'(AbstractGrammar.Lab(_,l)) = Label.toString l

    fun ppId'(AbstractGrammar.Id(_,_,n)) = Name.toString n
    fun ppId x = ppQuoted(ppId' x)

    fun ppLongid'(AbstractGrammar.ShortId(_,x))  = ppId' x
      | ppLongid'(AbstractGrammar.LongId(_,y,l)) = ppLongid' y ^ "." ^ ppLab' l
    fun ppLongid y = ppQuoted(ppLongid' y)


    val classLab	= (ppLab,   ["label"])
    val classVId	= (ppVId,   ["value","or","constructor"])
    val classValVId	= (ppVId,   ["value"])
    val classConVId	= (ppVId,   ["constructor"])
    val classTyCon	= (ppTyCon, ["type"])
    val classTyVar	= (ppTyVar, ["type","variable"])
    val classStrId	= (ppStrId, ["structure","or","functor"])
    val classSigId	= (ppSigId, ["signature"])

    fun ppUnbound((ppId,class), id) =
	  textpar(["unknown"] @ class @ [ppId id])
    fun ppUnboundImport((ppId,class), id) =
	  textpar(class @ [ppId id,"is","not","exported","by","component"])

    fun ppError(InfixMisplaced vid) =
	  textpar["misplaced","infix","identifier",ppVId vid]
      | ppError(AssocConflict(vid1,vid2)) =
	  textpar["conflicting","infix","associativity","between","operators",
		  ppVId vid1,"and",ppVId vid2]
      (* Unbound identifiers *)
      | ppError(VIdUnbound vid) =
	  ppUnbound(classVId, vid)
      | ppError(TyConUnbound tycon) =
	  ppUnbound(classTyCon, tycon)
      | ppError(TyVarUnbound tyvar) =
	  ppUnbound(classTyVar, tyvar)
      | ppError(StrIdUnbound strid) =
	  ppUnbound(classStrId, strid)
      | ppError(SigIdUnbound sigid) =
	  ppUnbound(classSigId, sigid)
      | ppError(LongStrIdNonStruct) =
	  textpar["module","in","long","identifier","is","not","a","structure"]
      | ppError(ConTyConShadowed(tycon, vid)) =
	  textpar["datatype",ppTyCon tycon,"of","constructor",
		  ppVId vid,"is","shadowed","by","another","type","of","the",
		  "same","name"]
      (* Expressions *)
      | ppError(ExpConArgSuperfluous) =
	  textpar["superfluous","constructor","argument"]
      | ppError(ExpRowLabDuplicate lab) =
	  textpar(["duplicate"] @ #2 classLab @ [ppLab lab,"in","record"])
      (* Patterns *)
      | ppError(PatConArgMissing) =
	  textpar["missing","constructor","argument","in","pattern"]
      | ppError(PatConArgSuperfluous) =
	  textpar["superfluous","constructor","argument","in","pattern"]
      | ppError(PatVIdDuplicate vid) =
	  textpar["duplicate","variable",ppVId vid,"in","pattern",
		  "or","binding","group"]
      | ppError(WithPatVIdDuplicate vid) =
	  textpar["pattern","variable",ppVId vid,"redefined",
		  "inside","value","binding"]
      | ppError(PatLongVIdVar) =
	  textpar["non-constructor","long","identifier","in","pattern"]
      | ppError(PatRowLabDuplicate lab) =
	  textpar(["duplicate"] @ #2 classLab @ [ppLab lab,"in","record"])
      | ppError(AppPatNonCon) =
	  textpar["application","of","non-constructor","in","pattern"]
      | ppError(AltPatInconsistent) =
	  textpar["inconsistent","pattern","alternative"]
      (* Types *)
      | ppError(TyRowLabDuplicate lab) =
	  textpar(["duplicate"] @ #2 classLab @ [ppLab lab,"in","record"])
      | ppError(TyVarSeqDuplicate tyvar) =
	  textpar(["duplicate"] @ #2 classTyVar @ [ppTyVar tyvar])
      | ppError(ValTyVarSeqDuplicate tyvar) =
	  textpar(["duplicate","or","shadowing"] @ #2 classTyVar @
		  [ppTyVar tyvar])
      (* Declarations and bindings *)
      | ppError(OpenDecNonStruct) =
	  textpar["module","in","open","declaration","is","not","a","structure"]
      | ppError(ReplicationDecConShadowed vid) =
	  textpar["constructor",ppVId vid,"of","replicated","datatype","is",
		  "not","in","scope","or","shadowed"]
      | ppError(FvalBindDuplicate vid) =
	  textpar["duplicate","function",ppVId vid,"in","binding","group"]
      | ppError(FvalBindArityInconsistent) =
	  textpar["inconsistent","function","arity","in","function","clause"]
      | ppError(FvalBindArityZero) =
	  textpar["no","arguments","in","function","clause"]
      | ppError(FvalBindNameInconsistent vid) =
	  textpar["inconsistent","function","name",ppVId vid,
		  "in","function","clause"]
      | ppError(FvalBindNameMissing) =
	  textpar["no","function","name","in","function","clause"]
      | ppError(FvalBindNameCon vid) =
	  textpar["redefining","constructor",ppVId vid,"as","value"]
      | ppError(FvalBindPatInvalid) =
	  textpar["invalid","function","clause"]
      | ppError(TypBindDuplicate tycon) =
	  textpar(["duplicate"] @ #2 classTyCon @
		  [ppTyCon tycon,"in","binding","group"])
      | ppError(DatBindDuplicate tycon) =
	  textpar(["duplicate"] @ #2 classTyCon @
		  [ppTyCon tycon,"in","binding","group"])
      | ppError(DatBindConDuplicate vid) =
	  textpar["duplicate","constructor",ppVId vid,"in","binding","group"]
      | ppError(ConBindDuplicate vid) =
	  textpar["duplicate","constructor",ppVId vid,"in","datatype"]
      | ppError(ExtBindDuplicate tycon) =
	  textpar(["duplicate"] @ #2 classTyCon @
		  [ppTyCon tycon,"in","binding","group"])
      | ppError(EconBindDuplicate vid) =
	  textpar["duplicate","constructor",ppVId vid,"in","binding","group"]
      | ppError(EconBindNonCon) =
	  textpar["non-constructor","on","constructor","binding",
		  "right","hand","side"]
      | ppError(StrBindDuplicate strid) =
	  textpar(["duplicate"] @ #2 classStrId @
		  [ppStrId strid,"in","binding","group"])
      | ppError(SigBindDuplicate sigid) =
	  textpar(["duplicate"] @ #2 classSigId @
		  [ppSigId sigid,"in","binding","group"])
      (* Structure expressions *)
      | ppError(AppStrExpNonFun) =
	  textpar["application","of","non-functor"]
      (* Specifications and descriptions *)
      | ppError(IncludeSpecNonStruct) =
	  textpar["signature","in","include","specification","is","not",
		  "a","structure"]
      | ppError(ReplicationSpecConShadowed vid) =
	  textpar["constructor",ppVId vid,"of","replicated","datatype","is",
		  "not","in","scope","or","shadowed"]
      | ppError(SpecFixDuplicate vid) =
	  textpar(["duplicate","fixity","specification","for"] @ #2 classVId @
		  [ppVId vid,"in","signature"])
      | ppError(SpecVIdDuplicate vid) =
	  textpar(["duplicate"] @ #2 classVId @ [ppVId vid,"in","signature"])
      | ppError(SpecTyConDuplicate tycon) =
	  textpar(["duplicate"] @ #2 classTyCon @
		  [ppTyCon tycon,"in","signature"])
      | ppError(SpecStrIdDuplicate strid) =
	  textpar(["duplicate"] @ #2 classStrId @
		  [ppStrId strid,"in","signature"])
      | ppError(SpecSigIdDuplicate sigid) =
	  textpar(["duplicate"] @ #2 classSigId @
		  [ppSigId sigid,"in","signature"])
      | ppError(ConDescDuplicate vid) =
	  textpar["duplicate","constructor",ppVId vid,"in","datatype"]
      | ppError(EconDescNonCon) =
	  textpar["non-constructor","on","constructor","description",
		  "right","hand","side"]
      (* Imports and items *)
      | ppError(ImpFixDuplicate vid) =
	  textpar(["duplicate","fixity","for"] @ #2 classVId @
		  [ppVId vid,"in","import"])
      | ppError(ImpVIdDuplicate vid) =
	  textpar(["duplicate"] @ #2 classVId @ [ppVId vid,"in","import"])
      | ppError(ImpTyConDuplicate tycon) =
	  textpar(["duplicate"] @ #2 classTyCon @ [ppTyCon tycon,"in","import"])
      | ppError(ImpStrIdDuplicate strid) =
	  textpar(["duplicate"] @ #2 classStrId @ [ppStrId strid,"in","import"])
      | ppError(ImpSigIdDuplicate sigid) =
	  textpar(["duplicate"] @ #2 classSigId @ [ppSigId sigid,"in","import"])
      | ppError(ConItemDuplicate vid) =
	  textpar["duplicate","constructor",ppVId vid,"in","datatype"]
      | ppError(ValItemUnbound vid) =
	  ppUnboundImport(classVId, vid)
      | ppError(TypItemUnbound tycon) =
	  ppUnboundImport(classTyCon, tycon)
      | ppError(DatItemUnbound tycon) =
	  ppUnboundImport(classTyCon, tycon)
      | ppError(ConItemUnbound vid) =
	  ppUnboundImport(classVId, vid)
      | ppError(ExtItemUnbound tycon) =
	  ppUnboundImport(classTyCon, tycon)
      | ppError(EconItemUnbound vid) =
	  ppUnboundImport(classVId, vid)
      | ppError(StrItemUnbound strid) =
	  ppUnboundImport(classStrId, strid)
      | ppError(SigItemUnbound sigid) =
	  ppUnboundImport(classSigId, sigid)
      | ppError(ConItemNonCon vid) =
	  textpar["value",ppVId vid,"exported","by","component","is",
		  "not","a","proper","constructor"]
      | ppError(EconItemNonCon vid) =
	  textpar["value",ppVId vid,"exported","by","component","is",
		  "not","a","proper","constructor"]
      (* Sharing translation *)
      | ppError(SharingExternalTy x) =
	  textpar(#2 classTyCon @ [ppId x,"is","external","to","signature"])
      | ppError(SharingExternalSig x) =
	  textpar(#2 classSigId @ [ppId x,"is","external","to","signature"])
      | ppError(SharingExternalStr x) =
	  textpar(#2 classStrId @ [ppId x,"is","external","to","signature"])


    fun ppShadowed((ppId,class), id) =
	  textpar(class @ [ppId id,"shadows","previous","one"])
    fun ppNamingConvention((ppId,class), id, examples) =
	vbox(
	    textpar(class @ ["identifier",ppId id,"violates","standard",
		    "naming","conventions,","which","suggest"] @ class @
		    ["names","of","the","form"]) ^^
	    indent(textpar examples)
	)

    fun ppWarning(VIdShadowed vid) =
	  ppShadowed(classVId, vid)
      | ppWarning(TyConShadowed tycon) =
	  ppShadowed(classTyCon, tycon)
      | ppWarning(TyVarShadowed tyvar) =
	  ppShadowed(classTyVar, tyvar)
      | ppWarning(StrIdShadowed strid) =
	  ppShadowed(classStrId, strid)
      | ppWarning(SigIdShadowed sigid) =
	  ppShadowed(classSigId, sigid)
      (* Conventions *)
      | ppWarning(LabConvention lab) =
	  ppNamingConvention(classLab, lab, ["foo,","123"])
      | ppWarning(VIdConvention vid) =
	  ppNamingConvention(classVId, vid,
		["foo,","fooBar,","Foo,","FooBar,","FOO,","FOO_BAR"])
      | ppWarning(ValVIdConvention vid) =
	  ppNamingConvention(classValVId, vid, ["foo,","foo',","fooBar"])
      | ppWarning(ConVIdConvention vid) =
	  ppNamingConvention(classConVId, vid,
		["Foo,","FooBar,","FOO,","FOO_BAR"])
      | ppWarning(TyConConvention tycon) =
	  ppNamingConvention(classTyCon, tycon, ["foo,","foo_bar"])
      | ppWarning(TyVarConvention tyvar) =
	  ppNamingConvention(classTyVar, tyvar, ["'foo,","''foo,","'foo_bar"])
      | ppWarning(StrIdConvention strid) =
	  ppNamingConvention(classStrId, strid, ["Foo,","FooBar"])
      | ppWarning(SigIdConvention sigid) =
	  ppNamingConvention(classSigId, sigid, ["FOO,","FOO_BAR"])


  (* Export *)

    fun error(region, e)   = Error.error(region, ppError e)
    fun warn(b, region, w) = Error.warn(b, region, ppWarning w)
end
