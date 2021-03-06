val assert=General.assert;
(*
 * Author:
 *   Leif Kornstaedt <kornstae@ps.uni-sb.de>
 *
 * Copyright:
 *   Leif Kornstaedt, 2002-2003
 *
 * Last change:
 *   $Date: 2007-04-07 18:11:54 $ by $Author: rossberg $
 *   $Revision: 1.27 $
 *)










structure Resolver: RESOLVER =
    struct
	fun expandUrl url =
	    Url.resolve (Url.fromString (OS.FileSys.getDir () ^ "/")) url

	structure Handler =
	    struct
		type handler = string * (Url.t -> Url.t option)
		type t = handler

		exception Syntax

		fun baseUrl url =
		    let
			val path = Url.getPath url
		    in
			case List.rev path of
			    ""::_ => url
			  | _ => Url.setPath (url, path @ [""])
		    end

		val default = ("default", SOME)

		fun root base =
		    let
			val base = expandUrl (baseUrl base)
			fun f rel =
			    if Url.isAbsolutePath rel then NONE
			    else SOME (Url.resolve base rel)
		    in
			("root " ^ Url.toStringRaw base, f)
		    end

		fun cacheUrl url =
		    let
			val path = Url.getPath url
			val path =
			    case Url.getDevice url of
				SOME c => String.str c::path
			      | NONE => path
			val path =
			    case Url.getAuthority url of
				SOME authority => authority::path
			      | NONE => path
			val path =
			    case Url.getScheme url of
				SOME scheme => scheme::path
			      | NONE => path
		    in
			Url.setPath (Url.empty, path)
		    end

		fun cache base =
		    let
			val base = expandUrl (baseUrl base)
			fun f url =
			    if isSome (Url.getScheme url) then
				SOME (Url.resolve base (cacheUrl url))
			    else NONE
		    in
			("cache " ^ Url.toStringRaw base, f)
		    end

		fun dropPrefix (x::xr, y::yr) =
		    if x = y then dropPrefix (xr, yr) else NONE
		  | dropPrefix (nil, ys) = SOME ys
		  | dropPrefix (_, _) = NONE

		fun position sep cs =
		    case dropPrefix (sep, cs) of
			SOME cr => SOME (nil, cr)
		      | NONE =>
			    case cs of
				c::cr =>
				    (case position sep cr of
					 SOME (prefix, suffix) =>
					     SOME (c::prefix, suffix)
				       | NONE => NONE)
			      | nil => NONE

		datatype elem = TEXT of char list | VAR of string

		fun parse cs =
		    case position [#"?", #"{"] cs of
			SOME (prefix, suffix) => TEXT prefix::parse' suffix
		      | NONE =>
			    case cs of
				_::_ => [TEXT cs]
			      | nil => nil
		and parse' cs =
		    case position [#"}"] cs of
			SOME (prefix, suffix) =>
			    VAR (String.implode prefix)::parse suffix
		      | NONE => raise Syntax

		exception MatchFailure

		structure StringMap = MkHashImpMap(String)

		fun match ([TEXT cs'], cs, _) =
		    if cs = cs' then () else raise MatchFailure
		  | match (TEXT cs'::rest, cs, env) =
		    (case dropPrefix (cs', cs) of
			 SOME cr => match (rest, cr, env)
		       | NONE => raise MatchFailure)
		  | match ([VAR x], cs, env) = StringMap.insert (env, x, cs)
		  | match (VAR x::TEXT cs'::rest, cs, env) =
		    (case position cs' cs of
			 SOME (prefix, suffix) =>
			     (StringMap.insert (env, x, prefix);
			      match (rest, suffix, env))
		       | NONE => raise MatchFailure)
		  | match (nil, cs, env) =
		    (case cs of
			 nil => ()
		       | _::_ => raise MatchFailure)
		  | match (_, _, _) = assert false

		fun instantiate (p, env) =
		    String.implode (List.concat (instantiate' (p, env)))
		and instantiate' (TEXT cs::rest, env) =
		    cs::instantiate' (rest, env)
		  | instantiate' (VAR x::rest, env) =
		    StringMap.lookupExistent (env, x)::instantiate' (rest, env)
		  | instantiate' (nil, _) = nil

		fun pattern' (p1, p2) url =
		    let
			val env = StringMap.map ()
		    in
			(match (p1, String.explode (Url.toStringRaw url), env);
			 SOME (Url.fromString (instantiate (p2, env))))
			handle (MatchFailure | Url.Malformed) => NONE
		    end

		fun prefix (s1, s2) =
		    let
			val p1 = [TEXT (String.explode s1), VAR "x"]
			val p2 = [TEXT (String.explode s2), VAR "x"]
		    in
			("prefix " ^ s1 ^ " -> " ^ s2, pattern' (p1, p2))
		    end

		fun pattern (s1, s2) =
		    let
			val p1 = parse (String.explode s1)
			val p2 = parse (String.explode s2)
		    in
			("pattern " ^ s1 ^ " -> " ^ s2, pattern' (p1, p2))
		    end

		fun custom (name, f) =
		    ("custom " ^ name, fn url => f url) (*handle _ => NONE)*)

		val sep = Config.pathSeparator

		fun isEsc c =
		    case Config.pathEscape of
			SOME c' => c = c'
		      | NONE => false

		fun token (c1::(cs as c2::cr), sep, prefix) =
		    if isEsc c1 then token (cr, sep, c2::prefix)
		    else if c1 = sep then
			(String.implode (List.rev prefix), cs, true)
		    else token (cs, sep, c1::prefix)
		  | token ([c], sep, prefix) =
		    if isEsc c then raise Syntax
		    else if c = sep then
			(String.implode (List.rev prefix), nil, true)
		    else (String.implode (List.rev (c::prefix)), nil, false)
		  | token (nil, _, prefix) =
		    (String.implode (List.rev prefix), nil, false)

		fun parse s = parse' (String.explode s)
		and parse' nil = [default]
		  | parse' [#"="] = nil
		  | parse' (#"r":: #"o":: #"o":: #"t":: #"="::cs) =
		    let
			val (arg, rest, _) = token (cs, sep, nil)
			val argUrl = Url.fromString arg
				     handle Url.Malformed => raise Syntax
		    in
			root argUrl::parse' rest
		    end
		  | parse' (#"c":: #"a":: #"c":: #"h":: #"e":: #"="::cs) =
		    let
			val (arg, rest, _) = token (cs, sep, nil)
			val argUrl = Url.fromString arg
				     handle Url.Malformed => raise Syntax
		    in
			cache argUrl::parse' rest
		    end
		  | parse' (#"p":: #"r":: #"e":: #"f":: #"i":: #"x"::
			    #"="::cs) =
		    (case token (cs, #"=", nil) of
			 (arg1, inter, true) =>
			     let
				 val (arg2, rest, _) = token (inter, sep, nil)
			     in
				 prefix (arg1, arg2)::parse' rest
			     end
		       | (_, _, false) => raise Syntax)
		  | parse' (#"p":: #"a":: #"t":: #"t":: #"e":: #"r":: #"n"::
			    #"="::cs) =
		    (case token (cs, #"=", nil) of
			 (arg1, inter, true) =>
			     let
				 val (arg2, rest, _) = token (inter, sep, nil)
			     in
				 pattern (arg1, arg2)::parse' rest
			     end
		       | (_, _, false) => raise Syntax)
		  | parse' cs =
		    let
			val (arg, rest, _) = token (cs, sep, nil)
			val argUrl = Url.fromString arg
				     handle Url.Malformed => raise Syntax
		    in
			root argUrl::parse' rest
		    end

		fun apply' ((name, f)::handlers, url, trace) =
		    (case f url of
			 SOME url' =>
			     (trace ("...[" ^ Url.toStringRaw url' ^
				     "] (" ^ name ^ ")\n");
			      SOME (url', handlers))
		       | NONE =>
			     (trace ("...[not applicable] (" ^ name ^ ")\n");
			      apply' (handlers, url, trace)))
		  | apply' (nil, _, trace) =
		    (trace ("...all handlers failed\n"); NONE)

		fun apply url handlers = apply' (handlers, url, ignore)

		fun tracingApply trace url handlers =
		    apply' (handlers, url, trace)
	    end

	datatype result =
	    FILE of string
	  | STRING of string
	  | DELEGATE of Url.t

	type resolver = { name: string,
			  handlers: Handler.t list,
			  memoizeMap: result option UrlMap.t option }
	type t = resolver

	local
	    val traceFlag =
		ref (isSome (OS.Process.getEnv "ALICE_TRACE_RESOLVER"))
	in
	    fun trace s =
		if !traceFlag then TextIO.output (TextIO.stdErr, s) else ()
	end

	fun resolver {name, handlers, memoize} =
	    {name = name, handlers = handlers,
	     memoizeMap = if memoize then SOME (UrlMap.map #[]) else NONE}

	fun exists (resolver as {memoizeMap = SOME map, ...}: resolver, url) =
	    (case UrlMap.lookupNew (map, url) of
		 UrlMap.EXISTING resultOpt => resultOpt
	       | UrlMap.NEW p =>
		     let
			 val resultOpt = exists' (resolver, url)
		     in
			 Promise.fulfill (p, resultOpt); resultOpt
		     end)
	  | exists (resolver as {memoizeMap = NONE, ...}, url) =
	    exists' (resolver, url)
	and exists' (resolver as {name, ...}, url) =
	    case (Url.getScheme url, ""(*dummy to emulate guard*)) of
		(SOME "x-oz", _) => (*--** hack for Alice-on-Mozart *)
		    SOME (FILE (Url.toStringRaw url))
	      | (SOME "http", _) =>
		    (let
			 val response = HttpClient.get url
		     in
			 if #statusCode response = 200 then
			     (trace ("[" ^ name ^ "] ...localize succeeded (" ^
				     Url.toString url ^ ")\n");
			      SOME (STRING (#body response)))
			 else NONE
		     end handle _ => NONE)
	      | ((SOME scheme, _) | (NONE, scheme)) =>
		    if String.isPrefix "delegate-" scheme then
			let
			    val scheme' =
				String.extract (scheme, size "delegate-", NONE)
			in
			    SOME (DELEGATE (Url.setScheme (url, SOME scheme')))
			end
		    else
			(let
			     val s = Url.toLocalFile url
			 in
			     if OS.FileSys.isDir s then NONE
			     else
				 (trace ("[" ^ name ^
					 "] ...localize succeeded (" ^
					 s ^ ")\n");
				  SOME (FILE s))
			 end handle (Url.NotLocal | OS.SysErr _) => NONE)

	fun localize (resolver as {name, handlers, ...}) url =
	    let
		fun trace' s = trace ("[" ^ name ^ "] " ^ s)
		val apply = Handler.tracingApply trace' url
	    in
		trace' ("localize request: " ^ Url.toStringRaw url ^ "\n");
		localize' (handlers, apply, resolver)
	    end
	and localize' (handlers, apply, resolver) =
	    case apply handlers of
		SOME (url', handlers') =>
		    let
			val url'' = expandUrl url'
		    in
			case exists (resolver, url'') of
			    result as SOME _ => result
			  | NONE => localize' (handlers', apply, resolver)
		    end
	       | NONE => NONE
    end
