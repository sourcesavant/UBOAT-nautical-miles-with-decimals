// Unity built-in shader source. Copyright (c) 2016 Unity Technologies. MIT license (see license.txt)

Shader "Standard (DWS, Tree Manufacture, Impostor Bake)"
{
    Properties
    {
        _Color("Color", Color) = (1,1,1,1)
        _MainTex("Albedo", 2D) = "white" {}

        _Cutoff("Alpha Cutoff", Range(0.0, 1.0)) = 0.5

        _Glossiness("Smoothness", Range(0.0, 1.0)) = 0.5
        _GlossMapScale("Smoothness Scale", Range(0.0, 2.0)) = 1.0

        [Gamma] _Metallic("Metallic", Range(0.0, 1.0)) = 0.0
        _MetallicGlossMap("Metallic", 2D) = "white" {}

        [ToggleOff] _SpecularHighlights("Specular Highlights", Float) = 1.0
        [ToggleOff] _GlossyReflections("Glossy Reflections", Float) = 1.0

        _BumpScale("Scale", Float) = 1.0
        _BumpMap("Normal Map", 2D) = "bump" {}

        _Parallax ("Height Scale", Range (0.005, 0.08)) = 0.02
        _ParallaxMap ("Height Map", 2D) = "black" {}

        _OcclusionStrength("Strength", Range(0.0, 1.0)) = 1.0
		_MipMapBiasMultiplier("MipMap Bias Multiplier", Range(0.0, 1.0)) = 1.0

        _EmissionColor("Color", Color) = (0,0,0)
        _EmissionMap("Emission", 2D) = "white" {}

        _DetailMask("Detail Mask", 2D) = "white" {}

        _DetailAlbedoMap("Detail Albedo x2", 2D) = "grey" {}
        _DetailNormalMapScale("Scale", Float) = 1.0
        _DetailNormalMap("Normal Map", 2D) = "bump" {}
        _DetailMetallicGlossMap("Detail MSO", 2D) = "white" {}

		_DamageMask("", 2D) = "black" {}
		_DamageMap("", 2D) = "white" {}
		_DissolveMaskScale("Dissolve Mask Scale", Float) = 0.25

        _SubsurfaceScatteringIntensity("Subsurface Scattering Intensity", Float) = 0.0

		[PerRendererData] _WetnessBiasScale("", Vector) = (0.0, 0.0, 0.0, 0.0)
		_WetnessMap("", 2D) = "white" {}

        [NoScaleOffset] _BumpSpecAOMap 		("Normal Map (GA) Specular (R) AO (B)", 2D) = "bump" {}
        [NoScaleOffset] _TranslucencyMap 	("Snow Mask (R) AO (G) Translucency (B) Smoothness (A)", 2D) = "white" {}

        _InitialBend("Wind Initial Bend", Float) = 1
		_Stiffness("Wind Stiffness", Float) = 1
		_Drag("Wind Drag", Float) = 1
        _NewNormal("Vertex Normal Multiply", Vector) = (0,0,0,0)

        _TranslucencyStrength 				("Translucency Strength", Color) = (0.2, 0.5, 0.4, 1.0)

		_DamageMapPreferredResolution("", Float) = 4096
		_WetnessMapPreferredResolution("", Float) = 512

		[Enum(UV0,0,UV1,1)] _UVWetnessMap("UV Set for wetness map", Float) = 0

		[Enum(UV0,0,UV1,1)] _UVSec("UV Set for secondary textures", Float) = 0

			// Blending state
			[HideInInspector] _Mode("__mode", Float) = 0.0
			[HideInInspector] _SrcBlend("__src", Float) = 1.0
			[HideInInspector] _DstBlend("__dst", Float) = 0.0
			[HideInInspector] _ZWrite("__zw", Float) = 1.0
	}

		CGINCLUDE
#define UNITY_SETUP_BRDF_INPUT MetallicSetup
			ENDCG

		SubShader
		{
			Tags { "RenderType" = "Opaque" "PerformanceChecks" = "False" }

			// ------------------------------------------------------------------
			//  Deferred pass
			Pass
		{
			Name "DEFERRED"
			Tags { "LightMode" = "Deferred" }

			ZWrite On
			ZTest LEqual
            Cull Off

			CGPROGRAM
			#pragma target 4.5
			#pragma exclude_renderers nomrt

			// -------------------------------------

			#pragma shader_feature _ _ALPHATEST_ON _ALPHABLEND_ON _ALPHAPREMULTIPLY_ON
			#pragma shader_feature _EMISSION
			#pragma shader_feature _METALLICGLOSSMAP
			//#pragma shader_feature _ _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
			#pragma shader_feature _ _SPECULARHIGHLIGHTS_OFF
			#pragma shader_feature ___ _DETAIL_MULX2
			#pragma shader_feature _PARALLAXMAP
			#pragma shader_feature COMPENSATE_EARTH_CURVATURE_PER_VERTEX
            #pragma shader_feature _TREE_LEAVES_MANUFACTURE _TREE_BARK_MANUFACTURE
			#pragma shader_feature _SNOW_SUPPORT_ON

			// EDIT START
			#pragma multi_compile _ _DISSOLVE _DAMAGE_MAP
			#pragma multi_compile _ _WETNESS_SUPPORT_ON
			#pragma multi_compile USE_CUSTOM_AMBIENT
			////#pragma multi_compile _ DIRLIGHTMAP_COMBINED
			//#pragma multi_compile _ DYNAMICLIGHTMAP_ON			// it's also inside multi_compile_prepassfinal
			//#pragma multi_compile _ LIGHTMAP_ON
			// EDIT END

            //#define USE_CUSTOM_AMBIENT 1
            #define _NORMALMAP 1
			#define UNITY_HDR_ON 1
			#define IMPOSTOR_BAKE 1

			#if defined(_TREE_LEAVES_MANUFACTURE)
				#undef _ALPHABLEND_ON
				#undef _ALPHAPREMULTIPLY_ON
				#define _ALPHATEST_ON 1
			#endif

			// prepassfinal
			//#pragma multi_compile _ LIGHTPROBE_SH
			//#pragma multi_compile _ SHADOWS_SHADOWMASK
			//#if defined(DYNAMICLIGHTMAP_ON) || defined(LIGHTMAP_ON)
			//	#define DIRLIGHTMAP_COMBINED 1
			//#endif
			#if !defined(DYNAMICLIGHTMAP_ON)
				#define LIGHTPROBE_SH 1
			#endif
			#if defined(USE_CUSTOM_AMBIENT) && !defined(DYNAMICLIGHTMAP_ON)
				#if !defined(LIGHTPROBE_SH)
					#define LIGHTPROBE_SH 1
				#endif
				#if defined(UNITY_LIGHT_PROBE_PROXY_VOLUME)
					#undef UNITY_INSTANCED_SH
				#endif
				#if defined(UNITY_LIGHT_PROBE_PROXY_VOLUME)
					#undef UNITY_LIGHT_PROBE_PROXY_VOLUME
				#endif
			#endif
			// end

			#pragma multi_compile_prepassfinal			// BEWARE: with this setting disabled, shadow masking is not supported in this shader, non-directional lightmap modes are also not supported
			#pragma multi_compile_instancing
			// Uncomment the following line to enable dithering LOD crossfade. Note: there are more in the file to uncomment for other passes.
			//#pragma multi_compile _ LOD_FADE_CROSSFADE

            #define DEFERRED_PASS 1

			#pragma vertex vertDeferred
			#pragma fragment fragDeferred

			#include "UnityStandardCore.cginc"

			ENDCG
		}
    }

    CustomEditor "StandardDWSShaderGUI"
}
