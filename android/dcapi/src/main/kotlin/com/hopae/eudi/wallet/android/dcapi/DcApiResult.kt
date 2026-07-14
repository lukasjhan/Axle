@file:OptIn(androidx.credentials.ExperimentalDigitalCredentialApi::class)

package com.hopae.eudi.wallet.android.dcapi

import android.content.Intent
import androidx.credentials.DigitalCredential
import androidx.credentials.GetCredentialResponse
import androidx.credentials.exceptions.GetCredentialUnknownException
import androidx.credentials.provider.PendingIntentHandler
import org.json.JSONObject

/** Marshals a Digital Credentials API outcome into the result [Intent] the platform expects back. */
object DcApiResult {

    /** Returns [response] (an SDK-produced DC API response string) to the Credential Manager caller. */
    fun setResponse(resultData: Intent, response: String) {
        PendingIntentHandler.setGetCredentialResponse(resultData, GetCredentialResponse(DigitalCredential(response)))
    }

    /** Returns a failure (declined, error) to the caller. */
    fun setError(resultData: Intent, message: String?) {
        PendingIntentHandler.setGetCredentialException(resultData, GetCredentialUnknownException(message ?: "error"))
    }

    /** Envelope for an ISO `org-iso-mdoc` DC API response: `{"protocol", "data":{"response"}}`. */
    fun mdocResponseJson(protocol: String, response: String): String =
        JSONObject().put("protocol", protocol).put("data", JSONObject().put("response", response)).toString()

    /**
     * Envelope for an OpenID4VP DC API response: `{"protocol", "data": <SDK response>}`. The SDK produces only
     * the inner `data` object (`{vp_token}` for `dc_api`, `{response:<JWE>}` for `dc_api.jwt`); the platform /
     * Credential Manager requires the outer `protocol` + `data` envelope, echoing the matched request protocol.
     * Recent Chrome rejects a response without top-level `protocol` (`JSONException: No value for protocol`).
     */
    fun openId4VpResponseJson(protocol: String, response: String): String =
        JSONObject().put("protocol", protocol).put("data", JSONObject(response)).toString()
}
