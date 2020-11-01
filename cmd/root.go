package cmd

import (
	"fmt"
	"github.com/spf13/cobra"
	"os"

	version "github.com/hahwul/mzap/pkg/version"
	zap "github.com/hahwul/mzap/pkg/zap"
	homedir "github.com/mitchellh/go-homedir"
	"github.com/spf13/viper"
)

var cfgFile, URLs, apiHosts, APIKey string
var options zap.OptionsZAP

// rootCmd represents the base command when called without any subcommands
var rootCmd = &cobra.Command{
	Use:   "mzap",
}

// Execute adds all child commands to the root command and sets flags appropriately.
// This is called by main.main(). It only needs to happen once to the rootCmd.
func Execute() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}

func init() {
	version.Banner()
	cobra.OnInitialize(initConfig)

	// Here you will define your flags and configuration settings.
	// Cobra supports persistent flags, which, if defined here,
	// will be global for your application.

	rootCmd.PersistentFlags().StringVar(&cfgFile, "config", "", "config file (default is $HOME/.mzap.yaml)")

	// Cobra also supports local flags, which will only run
	// when this action is called directly.
	rootCmd.PersistentFlags().StringVar(&APIKey, "apikey", "", "ZAP API Key / if you disable apikey, not use this option")
	rootCmd.PersistentFlags().StringVar(&URLs, "urls", "", "URL list file / e.g --urls hosts.txt")
	rootCmd.PersistentFlags().StringVar(&apiHosts, "apis", "http://localhost:8090", "ZAP API Host(s) address\ne.g --apis http://localhost:8090,http://192.168.0.4:8090")

	options = zap.OptionsZAP {
		APIKey: APIKey,
	}
	_= options
}

// initConfig reads in config file and ENV variables if set.
func initConfig() {
	if cfgFile != "" {
		// Use config file from the flag.
		viper.SetConfigFile(cfgFile)
	} else {
		// Find home directory.
		home, err := homedir.Dir()
		if err != nil {
			fmt.Println(err)
			os.Exit(1)
		}

		// Search config in home directory with name ".mzap" (without extension).
		viper.AddConfigPath(home)
		viper.SetConfigName(".mzap")
	}

	viper.AutomaticEnv() // read in environment variables that match

	// If a config file is found, read it in.
	if err := viper.ReadInConfig(); err == nil {
		fmt.Println("Using config file:", viper.ConfigFileUsed())
	}
}
