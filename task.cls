public with sharing class SMFGLMSAssetDedupResponseProcessor implements IintMsgCalloutResponseProcessor {
    public Response response;

    public class Response {
        public Header header;
        public Data data;
    }

    public class Header {
        public String msgID;
        public String reqSystem;
        public String reqType;
        public String userId;
        public String responseCode;
        public String responseTimeStamp;
        public String status;
        public String token;
        public String password;
        public String responseMsg;
    }

    public class Data {
        public String application;
        public String assetDetailsDedupeDataObject;
    }

    public static SMFGLMSAssetDedupResponseProcessor parse(String json) {
        System.debug('json=====================> '+json);
        
        // Option 1: Clean the timestamp format before parsing
        // This regex replaces timestamp patterns like "Fri May 23 18:40:17 IST 2025" with a simple string
        String cleanedJson = json.replaceAll('"responseTimeStamp":"[^"]*"', '"responseTimeStamp":"' + System.now().format() + '"');
        
        try {
            return (SMFGLMSAssetDedupResponseProcessor) System.JSON.deserialize(cleanedJson, SMFGLMSAssetDedupResponseProcessor.class);
        } catch (Exception e) {
            System.debug('JSON Parsing Error: ' + e.getMessage());
            // Option 2: Use manual parsing as fallback
            return parseManually(json);
        }
    }
    
    // Alternative manual parsing method
    private static SMFGLMSAssetDedupResponseProcessor parseManually(String json) {
        try {
            Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(json);
            
            SMFGLMSAssetDedupResponseProcessor processor = new SMFGLMSAssetDedupResponseProcessor();
            processor.response = new Response();
            
            Map<String, Object> responseMap = (Map<String, Object>) jsonMap.get('response');
            if (responseMap != null) {
                // Parse header
                Map<String, Object> headerMap = (Map<String, Object>) responseMap.get('header');
                if (headerMap != null) {
                    processor.response.header = new Header();
                    processor.response.header.msgID = (String) headerMap.get('msgID');
                    processor.response.header.reqSystem = (String) headerMap.get('reqSystem');
                    processor.response.header.reqType = (String) headerMap.get('reqType');
                    processor.response.header.userId = (String) headerMap.get('userId');
                    processor.response.header.responseCode = (String) headerMap.get('responseCode');
                    processor.response.header.responseTimeStamp = (String) headerMap.get('responseTimeStamp');
                    processor.response.header.status = (String) headerMap.get('status');
                    processor.response.header.token = (String) headerMap.get('token');
                    processor.response.header.password = (String) headerMap.get('password');
                    processor.response.header.responseMsg = (String) headerMap.get('responseMsg');
                }
                
                // Parse data
                Map<String, Object> dataMap = (Map<String, Object>) responseMap.get('data');
                if (dataMap != null) {
                    processor.response.data = new Data();
                    processor.response.data.application = (String) dataMap.get('application');
                    processor.response.data.assetDetailsDedupeDataObject = (String) dataMap.get('assetDetailsDedupeDataObject');
                }
            }
            
            return processor;
        } catch (Exception e) {
            System.debug('Manual parsing error: ' + e.getMessage());
            return null;
        }
    }
    
    public static String process(Map<String,Object> dataInfo, String resPayload){
        ResponseJson responseWrapper = new ResponseJson();
        String loanApplicationId = '';
        String decryptResponse = '';
        try{
            loanApplicationId = (String)dataInfo.get('recordId');
            LoanAppl__c loanApp = [select Id,LMSPDDAssetDedupeMsg__c from LoanAppl__c where Id = :loanApplicationId];
            Common_Configuration__mdt comConfigMdt = [SELECT Id,TW_Algo_Type__c,TW_Algo_Key__c,TW_Algo_String__c,TW_IVString__c FROM Common_Configuration__mdt where JL_Algorithm_Name__c =: 'SyncCallout' LIMIT 1];
            decryptResponse = EncryptApex.decryptString(comConfigMdt.TW_Algo_Type__c,comConfigMdt.TW_Algo_Key__c,'',false,resPayload);
            System.debug('decrypt===============> '+decryptResponse);
            Map<String, Object> parameter = (Map<String, Object>) JSON.deserializeUntyped(decryptResponse);
           SMFGLMSAssetDedupResponseProcessor wrap = new SMFGLMSAssetDedupResponseProcessor();
            wrap = SMFGLMSAssetDedupResponseProcessor.parse((String)parameter.get('response')); 
            System.debug('wrap=========>26 onboarding '+wrap);
            
            if(wrap != null && wrap.response != null && wrap.response.header != null){
                if(wrap.response.header.responseCode != null && wrap.response.header.responseCode == '0000' && 
                   wrap.response.header.responseMsg != null && wrap.response.header.responseMsg == 'No Match'){
                     System.debug('inside if - No Match');
                    loanApp.LMSPDDAssetDedupeMsg__c = 'No match';
                }else if(wrap.response.header.responseCode != null && wrap.response.header.responseCode == '0000' && 
                        wrap.response.header.responseMsg != null && wrap.response.header.responseMsg == 'Match'){
                    System.debug('inside else if - Match');
                    loanApp.LMSPDDAssetDedupeMsg__c = 'Match';
                }
            }
           update loanApp;          
        }catch (Exception e) {
            System.debug('Exception: ' + e.getMessage() + ' Line Number: ' + e.getLineNumber());
            GlobalUtility.logMessage('Error', 'SMFGLMSAssetDedupResponseProcessor class', 
                                     'Process', null, null, e.getMessage() + ' line ' + e.getLineNumber(), null, e, null);
            responseWrapper.Message = e.getMessage();
        }
        return decryptResponse;
    }
    
    public void process(List<IntgMsg__c> msgs){
        if(!msgs.isEmpty()){
            List<IntgConfig__mdt> intConfigMdt = [
                SELECT ID,Is_Simulated__c,Doc_API_for_response__c
                FROM IntgConfig__mdt 
                WHERE Svc__c =:msgs[0].Svc__c AND Is_Sync__c = False AND BU__c = : msgs[0].BU__c ];
            Map<String,Object> dataInfo = new Map<String,Object>();
            dataInfo.put('recordId',msgs[0].RefId__c);
            String str = '';
            if(intConfigMdt[0].Doc_API_for_response__c){
                str = ContentVersionUtil.versiondata(msgs[0].Id, 'response.txt');
            }
            else{
                str = msgs[0].Resp__c;
            }
            String finalstring = SMFGLMSAssetDedupResponseProcessor.process(dataInfo,str);
            if(finalstring != null && !String.isBlank(finalstring)){
                IntgMsg__c msdObj = new IntgMsg__c();
                msdObj.Id = msgs[0].Id;
                msdObj.IsProcessed__c = true;
                update msdObj;
            }
        }
        else{
            GlobalUtility.logMessage('Error', 'SMFGLMSAssetDedupResponseProcessor class', 
                                     'Process', null, null, 'List has no Rows returned', null, null, null);
        }
    }
    
    private class ResponseJson{
        public String Status;
        public String recordId;
        public String Message;
    }
}