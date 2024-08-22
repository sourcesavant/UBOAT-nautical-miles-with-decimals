Shader "CTI/LOD Billboard" {
	Properties{

		_Snow("snow sharpness", Range(1,10)) = 5
		_NormalInfluence("Normal Influence", Range(0,1)) = 0.3

		[Space(5)]
		_HueVariation 							("Color Variation (RGB) Strength (A)", Color) = (0.9,0.5,0.0,0.1)

		[Space(5)]
		[NoScaleOffset] _MainTex 				("Albedo (RGB) Alpha/Occlusion (A)", 2D) = "white" {}
		_Cutoff 								("Alpha Cutoff", Range(0,0.45)) = 0.3
		_AlphaLeak 								("Alpha Leak Suppression", Range(0.5,1.0)) = 0.6
		
		[Space(5)]
		[NoScaleOffset] _BumpTex 				("Normal (AG) Translucency(R) Smoothness(B)", 2D) = "bump" {}
		_SpecColor 								("Specular", Color) = (0.2,0.2,0.2)

		[Space(5)]
		_TranslucencyStrength 					("Translucency Strength", Range(0,1)) = .5
		_ViewDependency 						("View Dependency", Range(0,1)) = 0.8

		_TreeHeightLimit 						("Tree Height Limit", Range(0,1)) = 1

		[Header(Wind)]
		[Space(3)]
		[Toggle(_EMISSION)] _UseWind			("Enable Wind", Float) = 0.0
		[Space(5)]
		_WindStrength							("Wind Strength", Float) = 1.0
		
		//[Space(10)]
		//_NormalFactor("Normal Factor (XYZ) ", Vector) = (2.6,2.6,2.6,0.0)

		[HideInInspector] _TreeScale 			("Tree Scale", Range(0,50)) = 1
		[HideInInspector] _TreeWidth 			("Tree Width Factor", Range(0,1)) = 1
	}
		CGINCLUDE
			#include "UnityShaderVariables.cginc"
		ENDCG

		SubShader{
		Tags{
			"Queue" = "AlphaTest"
			"IgnoreProjector" = "True"
			"RenderType" = "CTI-Billboard"
			"DisableBatching" = "LODFading"
		}
		
		LOD 200
		Cull Off

		CGPROGRAM
		#pragma surface surf StandardTranslucent vertex:BillboardVertInit finalgbuffer:FinalGBufferDWS nolightmap nodirlightmap nodynlightmap keepalpha addshadow noinstancing dithercrossfade nofog
		// addshadow
		#pragma target 4.5
		#pragma multi_compile USE_CUSTOM_AMBIENT
		#pragma multi_compile __ LOD_FADE_CROSSFADE
		#pragma multi_compile_local SPEEDTREE_SHADER
		#pragma shader_feature _EMISSION

		#define IS_LODTREE
		#define IS_SURFACESHADER

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

		#include "CTI_BillboardVertex.cginc"
		#include "CTI_TranslucentLighting.cginc"

		sampler2D _MainTex;
		sampler2D _BumpTex;

		float _Cutoff;
		float _AlphaLeak;
		half4 _HueVariation;

		half _TranslucencyStrength;
		half _ViewDependency;

		half _Snow;
		half _NormalInfluence;

		half            _Lux_SnowAmount;
		fixed4          _Lux_SnowColor;
		fixed3          _Lux_SnowSpecColor;


		// All other inputs moved to include

		void BillboardVertInit(inout appdata_bb v, out Input o) {
			UNITY_INITIALIZE_OUTPUT(Input,o);
			AFSBillboardVert(v);
			o.uv_MainTex = v.texcoord;
			o.color.rgb = v.color.rgb;
			UNITY_TRANSFER_DITHER_CROSSFADE(o, v.vertex)
		}

		void FinalGBufferDWS(Input IN, SurfaceOutputStandardTranslucent o, inout half4 outGBuffer0, inout half4 outGBuffer1, inout half4 outGBuffer2, inout half4 emission)
		{
			// RT0: diffuse color (rgb), occlusion (a) - sRGB rendertarget
			//outGBuffer0 = half4(data.diffuseColor, data.occlusion);

			// RT1: spec color (rgb), smoothness (a) - sRGB rendertarget
			//outGBuffer1 = half4(data.specularColor, data.smoothness);

			// RT2: normal (rgb), --unused, very low precision-- (a)
			//outGBuffer2 = half4(data.normalWorld * 0.5f + 0.5f, _SurfaceType);

			//outGBuffer2.a = _SurfaceType;

			//UnityStandardDataApplyWeightToGbuffer(outGBuffer0, outGBuffer1, outGBuffer2, o.Alpha);
			//emission *= o.Alpha;
		}

		void surf(Input IN, inout SurfaceOutputStandardTranslucent o) {

			#if UNITY_VERSION < 2017
    			UNITY_APPLY_DITHER_CROSSFADE(IN)
   			#endif

			fixed4 c = tex2D(_MainTex, IN.uv_MainTex);
			clip(c.a - _Cutoff);

			o.Albedo = c.rgb;
			//	Add Color Variation
			o.Albedo = lerp(o.Albedo, (o.Albedo + _HueVariation.rgb) * 0.5, IN.color.r * _HueVariation.a);

			float4 normal = tex2D(_BumpTex, IN.uv_MainTex);
			o.Normal.xy = normal.ag * 2 - 1;
			o.Normal.z = sqrt(1 - saturate(dot(o.Normal.xy, o.Normal.xy)));

			// breaks translucency...
			// o.Normal = lerp(o.Normal, normalize(o.Normal + float3(0,0.975,0.0) ), IN.color.b);

			o.Translucency = (normal.r) * _TranslucencyStrength;
			o.ScatteringPower = _ViewDependency;
			
			o.Specular = _SpecColor;
			o.Smoothness = normal.b;
		
			c.a = (c.a <= _AlphaLeak) ? 1 : c.a; // Eliminate alpha leaking into ao
			o.Occlusion = c.a * 2 - 1;



			fixed3 wNormal = o.Normal; // WorldNormalVector(IN, o.Normal);
			//saturate(1.0 - lux.worldNormal.y - baseSnowAmount * 0.25)
			//o.Albedo = lerp(half3(1,1,1), o.Albedo, 1.0 - wNormal.y);
			//half snow = pow( saturate(wNormal.y) * trngls.r, 4);

			half normalInfluence = lerp(1, wNormal.y /*saturate(wNormal.y + 1)*/, _NormalInfluence);

			half baseSnowAmount = saturate(_Lux_SnowAmount * 1.75) * o.Occlusion; // *IN.color.a;

			half snow = saturate(baseSnowAmount - saturate(1 - normalInfluence - baseSnowAmount * 0.25));
			//snow *= trngls.r;
			//BlendValue = saturate ( (CrrentBlendStrength - ( 1.0 - Mask)) / _Sharpness );
			//snow = saturate((snow) * _Snow); // / 20 );
			snow *= snow;
															//  Sharpen snow
															//		snow = saturate(snow * 1.0 * (2.0 - _Lux_SnowAmount));
															//		snow = smoothstep(0.5, 1, snow);

			o.Albedo = lerp(o.Albedo, _Lux_SnowColor.xyz, snow);


		}
		ENDCG

		// Pass to render object as a shadow caster
/*		Pass{
		Name "ShadowCaster"
		Tags{ "LightMode" = "ShadowCaster" }
//		Cull Front

		CGPROGRAM
			#pragma vertex vert_surf
			#pragma fragment frag_surf
			#pragma target 3.0
			#pragma multi_compile_shadowcaster
			#pragma multi_compile __ LOD_FADE_CROSSFADE
			#include "HLSLSupport.cginc"
			#include "UnityCG.cginc"
			#include "Lighting.cginc"

			#define UNITY_PASS_SHADOWCASTER
			#include "Includes/CTI_BillboardVertex.cginc"

			sampler2D _MainTex;

			struct v2f_surf {
				V2F_SHADOW_CASTER;
				float2 hip_pack0 : TEXCOORD1;
				//#ifdef LOD_FADE_CROSSFADE
				//	half3 ditherScreenPos : TEXCOORD2;
				//#endif
				UNITY_DITHER_CROSSFADE_COORDS_IDX(2)
			};

			float4 _MainTex_ST;

			v2f_surf vert_surf(appdata_bb v) {
				v2f_surf o;
				AFSBillboardVert(v);
				o.hip_pack0.xy = TRANSFORM_TEX(v.texcoord, _MainTex);
				//UNITY_TRANSFER_DITHER_CROSSFADE(o, v.vertex)
				TRANSFER_SHADOW_CASTER_NORMALOFFSET(o)
				UNITY_TRANSFER_DITHER_CROSSFADE_HPOS(o, o.pos)
				return o;
			}
			fixed _Cutoff;

			float4 frag_surf(v2f_surf IN) : SV_Target{
				UNITY_APPLY_DITHER_CROSSFADE(IN)
				half alpha = tex2D(_MainTex, IN.hip_pack0.xy).a;
				//	alpha = (unity_LODFade.x > 0) ? alpha * unity_LODFade.x : alpha;
				clip(alpha - _Cutoff);
				SHADOW_CASTER_FRAGMENT(IN)
			}
		ENDCG
	} */

		///
	}
		FallBack "Transparent/Cutout/VertexLit"
}
