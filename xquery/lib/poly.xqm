module namespace poly = "http://kitwallace.co.uk/poly";

declare variable $poly:solids := doc("/db/apps/3d/data/flat_solids.xml")/solids;
declare variable $poly:coordinates := collection("/db/apps/3d/solids")/solids;
declare variable $poly:conwayOperators := doc("/db/apps/3d/data/conwayOperators.xml")/operators;
declare variable $poly:modulations := doc("/db/apps/3d/data/modulation.xml")/modulations;

declare function poly:clean-name($name) {
  replace(replace(replace(replace($name,"-","_"),"\(","_"),"\)","_"),",","_")
};

declare function poly:solid($id) {
   let $solid := $poly:solids/solid[id=$id]          
   let $coordinates := $poly:coordinates/solid[id=$id]
   return
      element solid {
         $solid/*,
         $coordinates/(url,vars,points,faces)
      }
};

declare function poly:parse-mccooey($id) {
  let $url := <url>http://dmccooey.com/polyhedra/{$id}.txt</url>
  let $request := <http:request method="get" href="{$url}"/>
  let $doc := http:send-request($request)
  return
  if (false()) then $doc else 
     if ($doc[1]/@status != "200") 
     then ()
     else 
  let $lines := tokenize($doc[2],"&#10;")
 (:  let $name := $lines[1] :)   (: bug -  actually can be multiple lines  :)
  let $vars :=
      for $vline in $lines[starts-with(.,"C")]  
      let $parts := tokenize($vline," = ")
      let $name := $parts[1]
      let $value := normalize-space($parts[2])
      where matches($value,"^(\d|\.)+$")    (: only constant values, not formula :)
      return 
           element var {
                element name {$name},
                element value {$value}
          }
   let $points := 
     for $pline in $lines[starts-with(.,"V")]
     let $parts := tokenize($pline," = ") 
     let $xyz := replace(replace($parts[2],"\(",""),"\)","")
     return  
          element point {$xyz}
   let $faces := 
      for $fline in $lines[starts-with(.,"{")]
      let $list := substring-after(substring-before($fline,"}"),"{")
      let $list := string-join(reverse(tokenize($list,",")),",")
      return
          element face {$list}
   let $edges :=
      let $raw_edges := 
         for $faces in $faces
         let $vertices := tokenize($faces,",")
         let $n := count($vertices)
         return
           for $i in (1 to $n)
           let $j :=  if ($i < $n) then $i + 1 else 1
           let $v0 := xs:integer($vertices[$i])
           let $v1 := xs:integer($vertices[$j])
           return concat(min(($v0,$v1)),",",max(($v0,$v1)))
      for $edge in distinct-values($raw_edges)
          return 
            element edge {$edge}

  return 
    element solid {
        $id,
        element url {$url/string()},
        element vars {$vars},
        element points {$points},
        element faces {$faces},
        element edges {$edges}
    }
};

declare function poly:parse-vrml($id,$url) {
  let $doc := httpclient:get(xs:anyURI($url),false(),())/httpclient:body
  let $text := util:binary-to-string($doc)
  let $rdoc := concat("<text>",replace(replace($text,"\}","</div>"),"\{","<div>"),"</text>")
  let $xml := util:parse($rdoc)/text/div

  let $points := 
       let $d := $xml/div[contains(.,"point [")]
       let $data:= substring-before(substring-after($d,"point ["),"]")
       for $s in tokenize($data,",")
       let $sn :=normalize-space($s)
       where $sn != ""
       return  
                element point { replace($sn," ",",") }
  let $faces := 
       for $d in $xml/div[contains(.,"coordIndex [")]
       let $data := substring-before(substring-after($d,"coordIndex ["),"]")
       for $face in tokenize($data,",-1,")
       let $indexes := tokenize(normalize-space($face),",")
       where count($indexes) > 2
       return  
         element face {string-join(reverse($indexes),",")}
   let $edges :=
      let $raw_edges := 
         for $faces in $faces
         let $vertices := tokenize($faces,",")
         let $n := count($vertices)
         return
           for $i in (1 to $n)
           let $j :=  if ($i < $n) then $i + 1 else 1
           let $v0 := xs:integer($vertices[$i])
           let $v1 := xs:integer($vertices[$j])
           return concat(min(($v0,$v1)),",",max(($v0,$v1)))
      for $edge in distinct-values($raw_edges)
          return 
            element edge {$edge}
    
  return 
     element solid { 
       element id {string($id)},
       element url{string($url)},
       element points {$points},
       element faces {$faces},
       element edges {$edges}
    }
};

declare function poly:solid-to-openscad($solid,$cleanid) {
  string-join(
    (
     concat("function ", $cleanid,"() = "),
     concat ("// source:  ",  $solid/url[1]),
     "// generated by  http://kitwallace.co.uk/3d/solid-index.xq",
     for $var in $solid/vars/var
        return concat ("let(" , $var/name, " = ", $var/value, ")"),
        
     concat('poly(name = "',$solid/name[1],'",'),

    
     let $facesides :=    for $face in $solid/faces/face
                          let $nfaces := count(tokenize($face,","))
                          return $nfaces
     for $sides in distinct-values($facesides)
     let $count := count($facesides[. = $sides])
     return
          concat("// ",$sides ," sided faces = ", $count),
    
     concat("vertices = [&#10;",
          string-join(
              for $point in $solid/points/point
              return concat("[",$point,"]")
              ,",&#10;")
              , "],"),
     concat("faces = [&#10;",
            string-join(
              for $face in $solid/faces/face
              return concat("[",$face,"]")
              ,",&#10;")
              , "]"),
     ");" 
     ),"&#10;"
    )
};

declare function poly:conway-to-openscad($formula) {
   if ($formula = "")
   then ""
   else 
   let $char := substring($formula,1,1)
   let $rest := substring($formula,2)
   let $operator := $poly:conwayOperators/operator[@char=$char]
   let $next := substring($rest,1,1)
   let $params := if ($next="(")
                  then substring-before(substring($rest,2),")")
                  else ()
   let $nparam := if ($next castable as xs:integer)
                  then  let $n :=  tokenize($rest,"\p{L}+")[1]  
                        return $n
                  else ()
   let $remainder := if ($params)
                     then substring(substring($rest,2),string-length($params)+2)
                     else if ($nparam)
                     then substring(substring($rest,2),string-length($nparam))
                     else $rest
   let $expression :=
      if ($operator)
      then concat($operator/@function,
                  "(",
                  poly:conway-to-openscad($remainder),
                  if ($params or $nparam) 
                  then concat(if (string-length($remainder) = 0) then "" else ",",$params,$nparam) 
                  else "",
                  ")")
      else (:  poly:conway-to-openscad($rest) :)
          $formula
   return 
      $expression
};
     

declare function poly:sequence($seq,$i) {

   let $s:=$seq[1]
   return
   if (exists($s))
   then 
      let $last := concat("solid_",$i -1)
      let $this := concat("solid_",$i )
      let $next := concat("solid_",$i + 1)
      let $sr := replace(replace(replace($s,"\$this",$this),"\$next",$next),"\$last",$last)
      let $j := if (contains($s,"$next")) then $i+1 else $i
      let $rest:=  poly:sequence(subsequence($seq,2),$j)
      return concat($sr,"&#10;",$rest)
   else ()
};

declare function poly:sequence($seq) {
   poly:sequence($seq,1)
};

declare function poly:make-openscad($solid) {
       let $source := request:get-parameter("src",())
       let $form := request:get-parameter("form",()) 
       let $conway1 := request:get-parameter("conway1",())
       let $conway2 := normalize-space(request:get-parameter("conway2",()))
       let $conway := if ($conway2 !="") then $conway2 else $conway1
       let $canon := request:get-parameter("canon",())
       let $plane := request:get-parameter("plane",())
       let $edge-radius := request:get-parameter("edge-radius",()) 
       let $vertex-radius := request:get-parameter("vertex-radius",())
       let $edge-sides := request:get-parameter("edge-sides",())
       let $depth := request:get-parameter("depth",())
       let $outer-inset-ratio := request:get-parameter("outer-inset-ratio",())
       let $inner-inset-ratio := request:get-parameter("inner-inset-ratio",())
       let $thickness := request:get-parameter("thickness",())
       let $openness := request:get-parameter("openness",())
       let $open-faces := request:get-parameter("open-faces",())
       let $place := request:get-parameter("place",())
       let $skew-alpha := request:get-parameter("skew-alpha",())
       let $skew-beta := request:get-parameter("skew-beta",())
       let $scale-x := request:get-parameter("scale-x",())
       let $scale-y := request:get-parameter("scale-y",())
       let $scale-z := request:get-parameter("scale-z",())
       let $modulate := request:get-parameter("selectFunction",())
       let $functionText := request:get-parameter("functionText",())
       let $catmull-clark-n := request:get-parameter("catmull-clark-n",())
       let $scale := request:get-parameter("scale",())
       let $format := request:get-parameter("format",())
       let $note := concat("// source=",$source," form=",$form," id =",$solid/id)
       let $cleanid := poly:clean-name($solid/id)
       let $source-os :=                   
                         if ($conway != "")
                         then
                            let $pconway := if (number($plane)> 0)
                                             then concat("K(",$plane,")",$conway)
                                             else $conway
                            let $cconway :=if (number($canon)> 0)
                                             then concat("N(",$canon,")",$pconway)
                                             else $pconway
                            return concat("// formula ",$conway,"&#10;","solid_1 = ",poly:conway-to-openscad($cconway),";")
                         else if ($source = "coordinates") 
                         then concat("solid_1 = ",$cleanid,"();")         
                         else ()  
       return if (not(exists($source-os))) then () else 
       let $skew-os := if (number($skew-alpha) !=0 or number($skew-beta) != 0) then concat("$next = skew($this,",$skew-alpha,",",$skew-beta,");")  else ()
       let $scale-os :=if (number($scale-x) != 1 or number($scale-y) != 1 or number($scale-z) != 1) then concat("$next = scale($this,[",string-join(($scale-x,$scale-y,$scale-z),","),"]);") else ()
       
       let $describe-os := "p_describe($this);"
       let $modulate-os := if ($modulate != "") then concat($functionText,"&#10;","$next = modulate($this);") else ()
       let $place-os := if ($place ="yes") then "$next = place($this);" else ()
       let $fn := concat("[",$open-faces,"]")
       let $openface-os := 
           if ($form="openface")
           then concat("$next = openface($this,outer_inset_ratio=",$outer-inset-ratio,",inner_inset_ratio=",$inner-inset-ratio,",depth=",$depth,",fn=",$fn,");")
           else ()
       let $cc-os := if (number($catmull-clark-n) > 0 ) then concat("$next = rcc($this,",$catmull-clark-n,");") else ()
       let $global := if ($form="net") then concat("thickness = ",$thickness,"; openness=",$openness,";") else()
       let $form-os :=
           if ($form=("solid","openface"))
           then "show_solid($this);"
           else if ($form="wire")
           then concat("{show_edges($this,",$edge-radius,",$fn=",$edge-sides,");&#10;",if (number($vertex-radius) > 0)  then concat("show_points($this,",$vertex-radius,",$fn=",$edge-sides,");") else () ,"}")
           else if ($form="net")
           then "p_net_render($this,p_create_net($this),complete=openness,colors=variedcolors);"
           else ()
       let $scaled-os := concat("scale(",$scale,") ",$form-os) 
       let $main-os := poly:sequence(($skew-os,$scale-os,$describe-os,$modulate-os,$place-os,$openface-os,$cc-os,$scaled-os))   
       let $coordinates-os := if ($source="coordinates")
                              then poly:solid-to-openscad($solid,$cleanid)  
                              else ()
       let $conway-os := util:binary-to-string(util:binary-doc("/db/apps/3d/openscad/conway.scad"))
       let $net-os := if ($form="net")
                        then util:binary-to-string(util:binary-doc("/db/apps/3d/openscad/netfns.scad"))
                        else ()
       return
         string-join(($note,$source-os,$global,$main-os,$coordinates-os,$conway-os,$net-os),"&#10;")
};
