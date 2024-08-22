Shader "Hidden/TerrainEngine/Splatmap/Standard-Base (DWS)" {
	Properties {
		_MainTex ("Base (RGB) Smoothness (A)", 2D) = "white" {}
		_MetallicTex ("Metallic (R)", 2D) = "white" {}

		// used in fallback on old cards
		_Color ("Main Color", Color) = (1,1,1,1)
	}

	Fallback Off
}
