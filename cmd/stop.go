package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
	zap "github.com/hahwul/mzap/pkg/zap"
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

			} else if  args[0] == "ajaxspider"{
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

	// Here you will define your flags and configuration settings.

	// Cobra supports Persistent Flags which will work for this command
	// and all subcommands, e.g.:
	// stopCmd.PersistentFlags().String("foo", "", "A help for foo")

	// Cobra supports local flags which will only run when this command
	// is called directly, e.g.:
	// stopCmd.Flags().BoolP("toggle", "t", false, "Help message for toggle")
}
