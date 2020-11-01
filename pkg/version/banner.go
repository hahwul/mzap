package version

import (
	"fmt"
	"os"
)

func Banner(){
	fmt.Fprintln(os.Stderr,"          ,/")
	fmt.Fprintln(os.Stderr,"        ,'/")
	fmt.Fprintln(os.Stderr,"      ,' /")
	fmt.Fprintln(os.Stderr,"    ,'  /_____,")
	fmt.Fprintln(os.Stderr,"  .'____    ,'                     MZAP")
	fmt.Fprintln(os.Stderr,"        /  ,'     [ Multiple target/agent ZAP scanning ]")
	fmt.Fprintln(os.Stderr,"       / ,'       [ "+VERSION+" ] [ by @hahwul ]")  
	fmt.Fprintln(os.Stderr,"      /,'")
	fmt.Fprintln(os.Stderr,"     /'")
	fmt.Fprintln(os.Stderr,"")
}
