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
        return (SMFGLMSAssetDedupResponseProcessor) System.JSON.deserialize(json, SMFGLMSAssetDedupResponseProcessor.class);
    }
     public static String process(Map<String,Object> dataInfo, String resPayload){
        ResponseJson responseWrapper = new ResponseJson();
        String loanApplicationId = '';
        String decryptresponse = '';
        try{
            loanApplicationId = (String)dataInfo.get('recordId');
            LoanAppl__c loanApp = [select Id,LMSPDDAssetDedupeMsg__c from LoanAppl__c where Id = :loanApplicationId];
            Common_Configuration__mdt comConfigMdt = [SELECT Id,TW_Algo_Type__c,TW_Algo_Key__c,TW_Algo_String__c,TW_IVString__c FROM Common_Configuration__mdt where JL_Algorithm_Name__c =: 'SyncCallout' LIMIT 1];
            decryptResponse = EncryptApex.decryptString(comConfigMdt.TW_Algo_Type__c,comConfigMdt.TW_Algo_Key__c,'',false,resPayload);
            System.debug('decrypt===============> '+decryptresponse);
            Map<String, Object> parameter = (Map<String, Object>) JSON.deserializeUntyped(decryptResponse);
           SMFGLMSAssetDedupResponseProcessor wrap = new SMFGLMSAssetDedupResponseProcessor();
            wrap = SMFGLMSAssetDedupResponseProcessor.parse((String)parameter.get('response')); 
            System.debug('wrap=========>26 onboarding '+wrap);
            
            if(wrap != null){
                if(wrap.response.header.responseCode!=null && wrap.response.header.responseCode=='0000' && wrap.response.header.responseMsg!=null && wrap.response.header.responseMsg=='No Match'){
                     System.debug('indside if');
                    loanApp.LMSPDDAssetDedupeMsg__c = 'No match';
                }else if(wrap.response.header.responseCode!=null && wrap.response.header.responseCode=='0000' && wrap.response.header.responseMsg!=null && wrap.response.header.responseMsg=='Match'){
                    System.debug('indside else if');
                    loanApp.LMSPDDAssetDedupeMsg__c = 'Match';
                }
            }
           Update loanApp;          
        }catch (Exception e) {
            system.debug('Exception'+e.getMessage() +' Line Number '+e.getLineNumber());
            GlobalUtility.logMessage('Error', 'SMFGLMSAssetDedupResponseProcessor class', 
                                     'Process', null, null, e.getMessage() + ' line ' + e.getLineNumber(), null, e, null);
            responseWrapper.Message =  e.getMessage();
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
            if(finalstring !=null || !String.IsBlank(finalstring)){
                IntgMsg__c msdObj = new IntgMsg__c();
                msdObj.Id = msgs[0].Id;
                msdObj.IsProcessed__c = true;
                Update msdObj;
            }
        }
        else{
            GlobalUtility.logMessage('Error', 'SMFGLMSAssetDedupResponseProcessor class', 
                                     'Process', null, null, 'List as no Rows return', null, null, null);
        }
    }
    
    private class ResponseJson{
        public String Status;
        public String recordId;
        public String Message;
    }
}


ExceptionIllegal value for primitive Line Number 15 
because ,"responseTimeStamp":"Fri May 23 18:40:17 IST 2025" is this
