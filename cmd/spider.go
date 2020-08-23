package cmd

import (
	"fmt"
	"github.com/spf13/cobra"
	zap "github.com/hahwul/mzap/pkg/zap"
)

// spiderCmd represents the spider command
var spiderCmd = &cobra.Command{
	Use:   "spider",
	Short: "Add ZAP spider",
	Run: func(cmd *cobra.Command, args []string) {
		if URLs != "" {
			zap.Spider(URLs,apiHosts, options)
		} else {
			fmt.Println("Please input --urls flag")
		}
	},
}

func init() {
	rootCmd.AddCommand(spiderCmd)

	// Here you will define your flags and configuration settings.

	// Cobra supports Persistent Flags which will work for this command
	// and all subcommands, e.g.:
	// spiderCmd.PersistentFlags().String("foo", "", "A help for foo")

	// Cobra supports local flags which will only run when this command
	// is called directly, e.g.:
	// spiderCmd.Flags().BoolP("toggle", "t", false, "Help message for toggle")
}
