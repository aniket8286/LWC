<td role="gridcell">
                            <lightning-button variant="brand" label={labelInitiateLMSPdd} title="Authorized" onclick={handleClick}             class="slds-m-left_x-small" >
                            </lightning-button>
                
                            <lightning-button variant="destructive" label="Reject" title="Reject" disabled={showRejectBtn} onclick={handleUpsert} class="slds-m-left_x-small"></lightning-button>
                    
                            <lightning-card title="Comment Box">
                                <lightning-textarea
                                style="padding-bottom: 10px;"
                                    label="Enter your comment"
                                    required
                                    value={comment}
                                    onchange={handleChange}
                                    message-when-value-missing="Comment is required!">
                                </lightning-textarea>
                                
                            </lightning-card>
                        </td>
