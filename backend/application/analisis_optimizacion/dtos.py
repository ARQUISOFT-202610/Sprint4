from pydantic import BaseModel

class AnalisisRequestDTO(BaseModel):
    empresa_id: str
    tipo_analisis: str
    requested_by_email: str

class AnalisisResponseDTO(BaseModel):
    analisis_id: str
    estado: str
