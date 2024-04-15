package main

import (
	"github.com/openbao/openbao/api"
	"github.com/openbao/openbao/sdk/plugin"
	ohplugin "github.com/open-horizon/openbao-exchange-auth/plugin"
	"log"
	"os"
)

// This plugin provides authentication support for openhorizon users within the bao.
//
// It uses the bao's framework to interact with the plugin system.
//
// This plugin must be configured by a bao admin through the /config API. Without the config, the plugin
// is unable to function properly.

func main() {
	apiClientMeta := &api.PluginAPIClientMeta{}
	flags := apiClientMeta.FlagSet()
	flags.Parse(os.Args[1:])

	tlsConfig := apiClientMeta.GetTLSConfig()
	tlsProviderFunc := api.VaultPluginTLSProvider(tlsConfig)

	if err := plugin.Serve(&plugin.ServeOpts{
		BackendFactoryFunc: ohplugin.Factory,
		TLSProviderFunc:    tlsProviderFunc,
	}); err != nil {
		log.Fatal(err)
	}
}
