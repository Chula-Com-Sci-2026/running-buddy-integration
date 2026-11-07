# Operator image for seeding and checks inside the cluster. It mirrors the Compose `tools`
# service (gateway image + scripts at /checks) and adds bcrypt for team Identity fixtures.
FROM cra/gateway:local
RUN pip install --no-cache-dir bcrypt==4.2.1
WORKDIR /checks
COPY scripts/ /checks/
RUN mkdir -p /contracts
CMD ["python", "check_flows.py"]
