package cmd

import (
	"fmt"

	zap "github.com/hahwul/mzap/pkg/zap"
	"github.com/spf13/cobra"
)

// stopCmd represents the stop command
var stopCmd = &cobra.Command{
	Use:   "stop (spider/ascan/ajaxspider/all)",
	Short: "Stop Scanning",
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Println("stop called")
		if len(args) >= 1 {
			if args[0] == "spider" {
				zap.StopSpider(apiHosts, options)
			} else if args[0] == "ascan" {
				zap.StopActiveScan(apiHosts, options)

			} else if args[0] == "ajaxspider" {
				zap.StopAjaxSpider(apiHosts, options)

			} else if args[0] == "all" {
				zap.StopSpider(apiHosts, options)
				zap.StopAjaxSpider(apiHosts, options)
				zap.StopActiveScan(apiHosts, options)
			}
		} else {
			fmt.Println("Please input scanning mode for stop")
		}
	},
}

func init() {
	rootCmd.AddCommand(stopCmd)
}
