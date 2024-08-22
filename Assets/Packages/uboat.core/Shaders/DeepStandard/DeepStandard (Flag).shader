// Unity built-in shader source. Copyright (c) 2016 Unity Technologies. MIT license (see license.txt)

Shader "Standard (DWS, Flag)"
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

		_DamageMask("", 2D) = "black" {}
		_DamageMap("", 2D) = "white" {}
		_DissolveMaskScale("Dissolve Mask Scale", Float) = 0.25

        _SubsurfaceScatteringIntensity("Subsurface Scattering Intensity", Float) = 0.0

		[PerRendererData] _WetnessBiasScale("", Vector) = (0.0, 0.0, 0.0, 0.0)
		_WetnessMap("", 2D) = "white" {}

		[PerRendererData] _FlagAnimationFrameCount ("", Integer) = 10
		[PerRendererData] _FlagAnimationVertexCount ("", Integer) = 10
		[PerRendererData] _FlagAnimationSpeed ("", Float) = 15

	    _TumbleStrength						("Tumble Strength", Range(-1,1)) = 0
	    _TumbleFrequency					("Tumble Frequency", Range(0,4)) = 1
	    _TimeOffset							("Time Offset", Range(0,2)) = 0.25
	    
	    //[Toggle(_EMISSION)] _EnableLeafTurbulence("Enable Leaf Turbulence", Float) = 0.0
	    _LeafTurbulence 					("Leaf Turbulence", Range(0,4)) = 0.2
	    _EdgeFlutterInfluence				("Edge Flutter Influence", Range(0,1)) = 0.25

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
        //  Shadow rendering pass
		Pass{
			Name "ShadowCaster"
			Tags { "LightMode" = "ShadowCaster" }

			ZWrite On
			ZTest LEqual
			Cull Off

			CGPROGRAM
			#pragma target 3.0

			// -------------------------------------


			#pragma shader_feature _ _ALPHATEST_ON _ALPHABLEND_ON _ALPHAPREMULTIPLY_ON
			//#pragma shader_feature _METALLICGLOSSMAP
			//#pragma shader_feature _PARALLAXMAP
			#pragma multi_compile_shadowcaster
			#pragma multi_compile_instancing
			// Uncomment the following line to enable dithering LOD crossfade. Note: there are more in the file to uncomment for other passes.
			//#pragma multi_compile _ LOD_FADE_CROSSFADE

			// EDIT START
			#pragma multi_compile _ _OPAQUE_SHADOW
			//#pragma multi_compile _ _DISSOLVE
			// EDIT END

			#define UNITY_HDR_ON 1
			#pragma multi_compile_local _FLAG

			#pragma vertex vertShadowCaster
			#pragma fragment fragShadowCaster

			#include "UnityStandardShadow.cginc"

			ENDCG
		}
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

			#pragma shader_feature _NORMALMAP
			#pragma shader_feature _ _ALPHATEST_ON _ALPHABLEND_ON _ALPHAPREMULTIPLY_ON
			#pragma shader_feature _EMISSION
			#pragma shader_feature _METALLICGLOSSMAP
			//#pragma shader_feature _ _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
			#pragma shader_feature _ _SPECULARHIGHLIGHTS_OFF
			#pragma shader_feature ___ _DETAIL_MULX2
			#pragma shader_feature _PARALLAXMAP
			#pragma shader_feature COMPENSATE_EARTH_CURVATURE_PER_VERTEX
            #pragma shader_feature _WETNESS_SUPPORT_ON
            #pragma shader_feature _SNOW_SUPPORT_ON

			#pragma multi_compile _ USE_CUSTOM_AMBIENT

			#define UNITY_HDR_ON 1
			#pragma multi_compile_local _FLAG

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
			
            #define DEFERRED_PASS 1

			#pragma vertex vertDeferred
			#pragma fragment fragDeferred

			#include "UnityStandardCore.cginc"

			ENDCG
		}

			// EDITS START

			Pass
		{
			Name "Motion Vectors"
			Tags{ "LightMode" = "MotionVectors" }

			ZTest LEqual
			Cull Off
			ZWrite Off

			CGPROGRAM
			#pragma multi_compile _ _DISSOLVE
			#pragma multi_compile USE_CUSTOM_AMBIENT
			//#pragma multi_compile _ _DEEP_PIPELINE

			#define _DEEP_PIPELINE 1
			#define UNITY_HDR_ON 1
			#pragma multi_compile_local _FLAG

            #pragma multi_compile_instancing

			#pragma vertex VertMotionVectors
			#pragma fragment FragMotionVectors

			#include "UnityStandardCore.cginc"
			ENDCG
		}

		// EDITS END

        // ------------------------------------------------------------------
        // Extracts information for lightmapping, GI (emission, albedo, ...)
        // This pass it not used during regular rendering.
        Pass
        {
            Name "META"
            Tags { "LightMode"="Meta" }

            Cull Off

            CGPROGRAM
            #pragma vertex vert_meta
            #pragma fragment frag_meta

            #pragma shader_feature _EMISSION
            #pragma shader_feature _METALLICGLOSSMAP
            //#pragma shader_feature _ _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
            #pragma shader_feature ___ _DETAIL_MULX2
            #pragma shader_feature EDITOR_VISUALIZATION

			#ifndef UNITY_PASS_META
				#define UNITY_PASS_META
			#endif
			#define UNITY_HDR_ON 1

            #include "UnityStandardMeta.cginc"
            ENDCG
        }
    }


    //FallBack "VertexLit"
    CustomEditor "StandardDWSShaderGUI"
}
