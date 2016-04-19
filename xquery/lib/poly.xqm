module namespace poly = "http://kitwallace.co.uk/poly";

declare variable  $poly:solids := doc("/db/apps/3d/data/flat_solids.xml")/solids;
declare variable  $poly:coordinates := collection("/db/apps/3d/solids")/solids;

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

declare function poly:solid-to-openscad($solid) {
  let $id := replace(replace(replace($solid/id,"-","_"),"\(","_"),"\)","_")
  return
  string-join(
    (
     concat("function ", $id,"() = "),
     concat ("// source:  ",  $solid/url[1]),
     "// generated by  http://kitwallace.co.uk/3d/polyhedra.xq",
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
     ");",
     concat("base=",$id,"();"),
     "solid=base;"
     
    ),"&#10;"
    )
};
