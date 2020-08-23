package cmd

import (
	"fmt"
	"github.com/spf13/cobra"
	zap "github.com/hahwul/mzap/pkg/zap"
)

// ajaxspiderCmd represents the ajaxspider command
var ajaxspiderCmd = &cobra.Command{
	Use:   "ajaxspider",
	Short: "Add AjaxSpider ZAP",
	Run: func(cmd *cobra.Command, args []string) {
		if URLs != "" {
			zap.AjaxSpider(URLs,apiHosts, options)
		} else {
			fmt.Println("Please input --urls flag")
		}	
	},
}

func init() {
	rootCmd.AddCommand(ajaxspiderCmd)

	// Here you will define your flags and configuration settings.

	// Cobra supports Persistent Flags which will work for this command
	// and all subcommands, e.g.:
	// ajaxspiderCmd.PersistentFlags().String("foo", "", "A help for foo")

	// Cobra supports local flags which will only run when this command
	// is called directly, e.g.:
	// ajaxspiderCmd.Flags().BoolP("toggle", "t", false, "Help message for toggle")
}
