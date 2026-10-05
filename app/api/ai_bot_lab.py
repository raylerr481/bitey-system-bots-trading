from fastapi import APIRouter

router = APIRouter(prefix='/api/v1/ai-bot-lab', tags=['ai-bot-lab'])

@router.get('/status')
def status():
    return {'source':'Bitey SBT AI Bot Lab','state':'WAITING_FOR_MT4','automatic_analysis':True,'automatic_parameter_application':False}

@router.get('/activity')
def activity():
    return {'items':[],'count':0}
