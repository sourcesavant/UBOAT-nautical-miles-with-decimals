// Unity built-in shader source. Copyright (c) 2016 Unity Technologies. MIT license (see license.txt)

Shader "Standard (DWS, Simple Water)"
{
    Properties
    {
        _Color("Color", Color) = (1,1,1,1)
        _MainTex("Albedo", 2D) = "white" {}

        _Cutoff("Alpha Cutoff", Range(0.0, 1.0)) = 0.5

        _Glossiness("Smoothness", Range(0.0, 1.0)) = 0.5
        _GlossMapScale("Smoothness Scale", Range(0.0, 1.0)) = 1.0

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

		[PerRendererData] _WetnessBiasScale("", Vector) = (0.0, 0.0, 0.0, 0.0)
		_WetnessMap("", 2D) = "white" {}

		_DamageMapPreferredResolution("", Float) = 4096
		_WetnessMapPreferredResolution("", Float) = 512

		_PerlinIntensity ("Perlin Intensity", Range(0,1)) = 1
		_ClipHeight ("Clip Height", Float) = 101

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

		Pass
        {
            Name "FORWARD SRP"
            Tags { "LightMode" = "ForwardSRP" }

            Blend [_SrcBlend] [_DstBlend]
			BlendOp Add, Max
            ZWrite [_ZWrite]

            CGPROGRAM
            #pragma target 4.5

            // -------------------------------------

            #pragma shader_feature _NORMALMAP
            #pragma shader_feature _ _ALPHATEST_ON _ALPHABLEND_ON _ALPHAPREMULTIPLY_ON
            #pragma shader_feature _EMISSION
            #pragma shader_feature _METALLICGLOSSMAP
            #pragma shader_feature ___ _DETAIL_MULX2
            //#pragma shader_feature _ _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
            #pragma shader_feature _ _SPECULARHIGHLIGHTS_OFF
            #pragma shader_feature _ _GLOSSYREFLECTIONS_OFF
            #pragma shader_feature _PARALLAXMAP

			// fwdbase
			#pragma multi_compile _ LIGHTPROBE_SH
			#pragma multi_compile _ SHADOWS_SHADOWMASK
			#if defined(SHADOWS_SHADOWMASK) && !defined(LIGHTPROBE_SH)
				#define LIGHTMAP_ON 1
				#define DIRLIGHTMAP_COMBINED 1
				#define DYNAMICLIGHTMAP_ON 1
			#endif
			#define FOG_EXP2 1
			// end

            //#pragma multi_compile_fwdbase
            #pragma multi_compile_fog
            #pragma multi_compile_instancing
            // Uncomment the following line to enable dithering LOD crossfade. Note: there are more in the file to uncomment for other passes.
            //#pragma multi_compile _ LOD_FADE_CROSSFADE

			#define _SIMPLE_WATER 1
			#define UNITY_HDR_ON 1

            #pragma vertex vertBase
            #pragma fragment fragForwardBaseSRP
            #include "UnityStandardCoreForward.cginc"

            ENDCG
        }
        // ------------------------------------------------------------------
        //  Shadow rendering pass
		Pass{
			Name "ShadowCaster"
			Tags { "LightMode" = "ShadowCaster" }

			ZWrite On ZTest LEqual

			CGPROGRAM
			#pragma target 3.0

			// -------------------------------------


			#pragma shader_feature _ _ALPHATEST_ON _ALPHABLEND_ON _ALPHAPREMULTIPLY_ON
			#pragma shader_feature _METALLICGLOSSMAP
			#pragma shader_feature _PARALLAXMAP
			#pragma multi_compile_shadowcaster
			#pragma multi_compile_instancing
			// Uncomment the following line to enable dithering LOD crossfade. Note: there are more in the file to uncomment for other passes.
			//#pragma multi_compile _ LOD_FADE_CROSSFADE

			#define _SIMPLE_WATER 1
			#define UNITY_HDR_ON 1

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

			Cull Off

			CGPROGRAM
			#pragma target 3.0
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

			//#pragma multi_compile_prepassfinal
			#pragma multi_compile_instancing
			// Uncomment the following line to enable dithering LOD crossfade. Note: there are more in the file to uncomment for other passes.
			//#pragma multi_compile _ LOD_FADE_CROSSFADE

			#define _SIMPLE_WATER 1
			#define UNITY_HDR_ON 1

			// prepassfinal
			#pragma multi_compile _ LIGHTPROBE_SH
			#pragma multi_compile _ SHADOWS_SHADOWMASK
			#if defined(SHADOWS_SHADOWMASK) && !defined(LIGHTPROBE_SH)
				#define LIGHTMAP_ON 1
				#define DIRLIGHTMAP_COMBINED 1
				#define DYNAMICLIGHTMAP_ON 1
			#endif
			// end

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
			Cull Back
			ZWrite Off

			CGPROGRAM
			#pragma multi_compile _ _DEEP_PIPELINE
			#pragma multi_compile _ USE_CUSTOM_AMBIENT

			#define _SIMPLE_WATER 1
			#define UNITY_HDR_ON 1

			#pragma vertex VertMotionVectors
			#pragma fragment FragMotionVectors

			#include "UnityStandardCore.cginc"
			ENDCG
		}

		// EDITS END

		Pass
		{
			Tags { "LightMode" = "UnderwaterMask1" }

			ZTest Always
			ZWrite On
			Cull Off

			Stencil
			{
				Pass IncrWrap
			}

			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			
			#include "UnityCG.cginc"

			struct appdata
			{
				float4 vertex : POSITION;
			};

			struct v2f
			{
				float4 vertex : SV_POSITION;
			};

			float _ClipHeight;
			
			v2f vert (appdata v)
			{
				v2f o;
				float4 posWorld = mul(unity_ObjectToWorld, v.vertex);
				v.vertex.y -= max(0.0, posWorld.y - _ClipHeight);
				o.vertex = UnityObjectToClipPos(v.vertex);
				return o;
			}
			
			fixed4 frag (v2f i) : SV_Target
			{
				return 0;
			}
			ENDCG
		}

		Pass
		{
			Tags { "LightMode" = "UnderwaterMask2" }

			ZTest Always
			ZWrite Off
			Cull Front
			Offset 0, 0

			Stencil
			{
				Ref 1
				ReadMask 1
				Comp Equal
			}

			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			
			#include "UnityCG.cginc"

			struct appdata
			{
				float4 vertex : POSITION;
			};

			struct v2f
			{
				float4 vertex : SV_POSITION;
			};

			float _ClipHeight;
			
			v2f vert (appdata v)
			{
				v2f o;
				float4 posWorld = mul(unity_ObjectToWorld, v.vertex);
				v.vertex.y -= max(0.0, posWorld.y - _ClipHeight);
				o.vertex = UnityObjectToClipPos(v.vertex);
				return o;
			}
			
			fixed4 frag (v2f i) : SV_Target
			{
				return 1;
			}
			ENDCG
		}

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
            #pragma shader_feature _ _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
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
