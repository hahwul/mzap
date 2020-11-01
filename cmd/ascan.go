package cmd

import (
	"fmt"
	zap "github.com/hahwul/mzap/pkg/zap"
	"github.com/spf13/cobra"
)

// ascanCmd represents the ascan command
var ascanCmd = &cobra.Command{
	Use:   "ascan",
	Short: "Add ActiveScan ZAP",
	Run: func(cmd *cobra.Command, args []string) {
		if URLs != "" {
			zap.ActiveScan(URLs, apiHosts, options)
		} else {
			fmt.Println("Please input --urls flag")
		}
	},
}

func init() {
	rootCmd.AddCommand(ascanCmd)
}
